#!/bin/bash
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Stopping All OAI Services"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "[1/4] หยุด UE..."
sudo pkill -9 nr-uesoftmodem 2>/dev/null || true
sudo ip link delete oaitun_ue1 2>/dev/null || true
echo "[2/4] หยุด gNB..."
sudo pkill -9 nr-softmodem 2>/dev/null || true
sudo fuser -k 4043/tcp 2>/dev/null || true
sudo fuser -k 2152/udp 2>/dev/null || true
echo "[3/4] หยุด Core Network..."
cd /home/srs/oai-cn5g-fed/docker-compose
sudo docker compose -f docker-compose-basic-nrf.yaml down
echo "[4/4] ตรวจสอบ..."
sleep 3
REMAIN=$(sudo docker ps | grep oai | wc -l)
[ "$REMAIN" -eq 0 ] && echo "✅ หยุดทุกอย่างสำเร็จ" ||   echo "⚠️  ยังมี Container ค้างอยู่ $REMAIN ตัว"
