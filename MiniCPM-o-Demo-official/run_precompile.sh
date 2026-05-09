#!/bin/bash
cd /home/LChuang/workspace/MiniCPM-o-Demo-official
pkill -f 'gateway.py|worker.py' 2>/dev/null
sleep 2
nohup env CUDA_VISIBLE_DEVICES=0 TORCHINDUCTOR_CACHE_DIR=./torch_compile_cache PYTHONPATH=. .venv/base/bin/python precompile.py > tmp/precompile.log 2>&1 &
echo "PRECOMPILE_PID=$!"
sleep 3
ls tmp/precompile.log
head -20 tmp/precompile.log
