"""
server.py — FastAPI + WebSocket server for MiniCPM-o 4.5 web demo (remote-compute mode).

架构（前后端真分离）：
  浏览器（Mac）—— 麦克风/摄像头/扬声器
  服务端（spark）—— 仅 GPU 推理

Wire protocol:
  Browser → Server:
    0x01 + float32 LE PCM   (16 kHz, mono, ~20ms 帧；客户端已重采样)
    0x02 + JPEG bytes       (浏览器摄像头帧, ~1 FPS)
    0x03 + JSON utf-8       ({"action":"start"|"stop"|"set_mode"|"ptt_start"|"ptt_stop"|"ping"})

  Server → Browser:
    0x10 + float32 LE PCM   (24 kHz TTS)
    UTF-8 JSON              {"type":"text"|"status"|"ready"|"pong"|"stats", ...}
"""
import asyncio
import io
import json
import logging
import os
import sys
import threading
from contextlib import asynccontextmanager

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import numpy as np
import librosa
from PIL import Image
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import FileResponse

sys.path.insert(0, os.path.dirname(__file__))

from audio_utils import VADProcessor, SAMPLE_RATE as VAD_SAMPLE_RATE
from inference_engine import load_model, run_inference, MAX_VIDEO_FRAMES

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s  %(name)s — %(message)s",
)
logger = logging.getLogger("server")

FRONTEND_DIR = os.path.join(os.path.dirname(__file__), "frontend")

# 客户端上传 PCM 假定为 16 kHz mono float32（与 VAD 一致）。
# 若客户端实际采样率不同，可在 0x03 set_mode 时携带 sample_rate 字段。
CLIENT_SAMPLE_RATE = VAD_SAMPLE_RATE  # 16000

# 单连接全局推理屏蔽标志（推理/说话期间丢弃上行 PCM，防止回声）
_inference_busy = False


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("[Startup] 加载模型（首次 ~60s）…")
    await asyncio.to_thread(load_model)
    logger.info("[Startup] 模型就绪，等待浏览器连接")
    yield


app = FastAPI(lifespan=lifespan)


@app.get("/")
async def serve_index():
    return FileResponse(os.path.join(FRONTEND_DIR, "index.html"))


@app.websocket("/ws")
async def websocket_endpoint(ws: WebSocket):
    global _inference_busy

    await ws.accept()
    logger.info(f"[WS] 客户端连接: {ws.client}")

    send_lock = asyncio.Lock()
    speech_queue: asyncio.Queue = asyncio.Queue(maxsize=2)
    video_frames: list[Image.Image] = []
    video_lock = asyncio.Lock()

    # 会话与模式状态
    session_active = False
    ptt_mode = False
    ptt_recording = False
    ptt_buffer: list[np.ndarray] = []
    ptt_lock = threading.Lock()

    vad = VADProcessor(aggressiveness=2)

    # ── 发送辅助 ─────────────────────────────────────────────────────────
    async def send_json(obj: dict):
        async with send_lock:
            await ws.send_text(json.dumps(obj))

    async def send_binary(data: bytes):
        async with send_lock:
            await ws.send_bytes(data)

    async def on_tts(data: bytes):
        await send_binary(data)

    async def on_text(token: str):
        await send_json({"type": "text", "data": token})

    async def on_status(state: str):
        global _inference_busy
        _inference_busy = state in ("processing", "speaking")
        await send_json({"type": "status", "state": state})

    async def on_stats(stats: dict):
        await send_json({"type": "stats", **stats})

    async def enqueue_speech(segment: np.ndarray):
        if speech_queue.full():
            try:
                speech_queue.get_nowait()
            except asyncio.QueueEmpty:
                pass
        await speech_queue.put(segment)

    await send_json({"type": "ready"})

    # ── 接收循环 ─────────────────────────────────────────────────────────
    async def message_receiver():
        nonlocal session_active, video_frames, ptt_mode, ptt_recording
        try:
            while True:
                msg = await ws.receive()
                if msg["type"] == "websocket.disconnect":
                    break
                if msg["type"] != "websocket.receive":
                    continue

                if "bytes" in msg and msg["bytes"]:
                    raw = msg["bytes"]
                    mtype = raw[0]
                    payload = raw[1:]

                    if mtype == 0x01:
                        # 客户端上传 PCM（16 kHz float32 mono）
                        if not session_active:
                            continue
                        if _inference_busy:
                            # 模型说话/推理时丢弃，防止 TTS 回声进 ASR
                            continue
                        try:
                            chunk = np.frombuffer(payload, dtype=np.float32)
                        except Exception:
                            continue

                        if ptt_mode:
                            if ptt_recording:
                                with ptt_lock:
                                    ptt_buffer.append(chunk.copy())
                        else:
                            segment = vad.feed(chunk)
                            if segment is not None:
                                logger.info(
                                    f"[VAD] 语音段 {len(segment)/CLIENT_SAMPLE_RATE:.1f}s → 队列"
                                )
                                await enqueue_speech(segment)

                    elif mtype == 0x02:
                        try:
                            img = Image.open(io.BytesIO(payload)).convert("RGB")
                            img = img.resize((320, 240), Image.BILINEAR)
                            async with video_lock:
                                video_frames.append(img)
                                if len(video_frames) > MAX_VIDEO_FRAMES:
                                    video_frames = video_frames[-MAX_VIDEO_FRAMES:]
                        except Exception as exc:
                            logger.debug(f"[WS] JPEG 解码失败: {exc}")

                    elif mtype == 0x03:
                        try:
                            ctrl = json.loads(payload.decode("utf-8"))
                        except Exception:
                            continue
                        action = ctrl.get("action")
                        if action == "start" and not session_active:
                            session_active = True
                            vad.reset()
                            await on_status("listening")
                            logger.info("[WS] 会话开始")
                        elif action == "stop" and session_active:
                            session_active = False
                            await on_status("idle")
                            logger.info("[WS] 会话停止")
                        elif action == "set_mode":
                            ptt_mode = ctrl.get("mode") == "ptt"
                            logger.info(f"[WS] 模式: {'PTT' if ptt_mode else 'VAD'}")
                        elif action == "ptt_start" and session_active:
                            with ptt_lock:
                                ptt_recording = True
                                ptt_buffer.clear()
                            await on_status("recording")
                            logger.info("[PTT] 开始录音")
                        elif action == "ptt_stop" and session_active:
                            with ptt_lock:
                                ptt_recording = False
                                audio = (
                                    np.concatenate(ptt_buffer)
                                    if ptt_buffer
                                    else None
                                )
                                ptt_buffer.clear()
                            if audio is not None:
                                trimmed, _ = librosa.effects.trim(audio, top_db=30)
                                logger.info(
                                    f"[PTT] {len(audio)/CLIENT_SAMPLE_RATE:.1f}s → "
                                    f"裁剪 {len(trimmed)/CLIENT_SAMPLE_RATE:.1f}s"
                                )
                                if len(trimmed) > CLIENT_SAMPLE_RATE * 0.3:
                                    await enqueue_speech(trimmed)
                                else:
                                    await on_status("listening")
                            else:
                                await on_status("listening")
                        elif action == "ping":
                            await send_json({"type": "pong"})

                elif "text" in msg and msg["text"]:
                    try:
                        ctrl = json.loads(msg["text"])
                        if ctrl.get("action") == "ping":
                            await send_json({"type": "pong"})
                    except Exception:
                        pass

        except WebSocketDisconnect:
            pass
        except Exception as exc:
            logger.warning(f"[WS] message_receiver 错误: {exc}")
        finally:
            await speech_queue.put(None)

    # ── 推理协调器 ─────────────────────────────────────────────────────
    async def inference_coordinator():
        try:
            while True:
                segment = await speech_queue.get()
                if segment is None:
                    break
                async with video_lock:
                    frames = list(video_frames)
                await run_inference(
                    audio_np=segment,
                    pil_frames=frames,
                    on_tts=on_tts,
                    on_text=on_text,
                    on_status=on_status,
                    on_stats=on_stats,
                )
                if session_active:
                    await on_status("listening")
        except Exception as exc:
            logger.error(f"[WS] inference 错误: {exc}", exc_info=True)

    try:
        await asyncio.gather(message_receiver(), inference_coordinator())
    except Exception as exc:
        logger.warning(f"[WS] 连接错误: {exc}")
    finally:
        logger.info(f"[WS] 客户端断开: {ws.client}")
