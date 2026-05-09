#!/bin/bash
cd /home/LChuang/workspace/MiniCPM-o-Demo-official
pkill -f 'worker.py|gateway.py' 2>/dev/null
sleep 2
rm -f tmp/worker_0.log tmp/worker_0.pid tmp/gateway.log tmp/gateway.pid tmp_start.log
CUDA_VISIBLE_DEVICES=0 nohup bash start_all.sh --http > tmp_start.log 2>&1 < /dev/null &
echo "LAUNCHED pid=$!"
sleep 2
ls tmp/
