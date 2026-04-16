#!/bin/bash
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Starting UE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
sudo pkill -9 nr-uesoftmodem 2>/dev/null || true
sudo ip link delete oaitun_ue1 2>/dev/null || true
sleep 2
echo "[INFO] รัน UE..."
cd /home/srs/openairinterface5g/cmake_targets/ran_build/build
sudo ./nr-uesoftmodem \
  -O /home/srs/oai-cn5g-fed/docker-compose/ran-conf/nr-ue.conf \
  --rfsim \
  --rfsimulator.serveraddr 127.0.0.1 \
  -C 3319680000 \
  -r 106 \
  --numerology 1 \
  --ssb 516
