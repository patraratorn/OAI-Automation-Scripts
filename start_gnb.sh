#!/bin/bash
set -e
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Starting gNB"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Auto-detect AMF IP ทุกครั้ง
AMF_IP=$(sudo docker inspect oai-amf 2>/dev/null |   python3 -c "
import sys,json
d=json.load(sys.stdin)
nets=d[0]['NetworkSettings']['Networks']
for v in nets.values():
    if v['IPAddress']:
        print(v['IPAddress']); break
" 2>/dev/null ||   sudo docker inspect oai-amf | grep '"IPAddress"' | grep -v '""' |   head -1 | grep -oP '\d+\.\d+\.\d+\.\d+')

[ -z "$AMF_IP" ] && echo "[ERROR] ไม่พบ AMF IP — Core รันอยู่ไหม?" && exit 1
echo "[INFO] AMF IP: $AMF_IP"

# Auto-detect Bridge
BRIDGE=$(ip link show | grep -E "demo-oai|br-" | head -1 |   awk -F': ' '{print $2}' | awk '{print $1}')
[ -z "$BRIDGE" ] && echo "[ERROR] ไม่พบ Bridge Interface" && exit 1

# เพิ่ม Bridge IP ถ้าหาย
sudo ip addr add 192.168.70.200/26 dev $BRIDGE 2>/dev/null || true
echo "[INFO] Bridge: $BRIDGE / gNB IP: 192.168.70.200"

# อัปเดต AMF IP ใน gnb.conf
sed -i "s/ipv4[[:space:]]*=[[:space:]]*\"[0-9.]*\"/ipv4       = \"${AMF_IP}\"/" /home/srs/oai-cn5g-fed/docker-compose/ran-conf/gnb.conf
ACTUAL=$(grep 'ipv4.*=.*"[0-9]' /home/srs/oai-cn5g-fed/docker-compose/ran-conf/gnb.conf | grep -oP '\d+\.\d+\.\d+\.\d+' | head -1)
[ "$ACTUAL" != "$AMF_IP" ] && echo "[ERROR] อัปเดต AMF IP ใน gnb.conf ไม่สำเร็จ" && exit 1
echo "[INFO] gnb.conf อัปเดต AMF IP → $AMF_IP สำเร็จ"

# Kill process เก่า
sudo pkill -9 nr-softmodem 2>/dev/null || true
sudo fuser -k 4043/tcp 2>/dev/null || true
sudo fuser -k 2152/udp 2>/dev/null || true
sleep 2

echo "[INFO] รัน gNB..."
cd /home/srs/openairinterface5g/cmake_targets/ran_build/build
sudo ./nr-softmodem -O /home/srs/oai-cn5g-fed/docker-compose/ran-conf/gnb.conf --sa --rfsim --rfsimulator.serveraddr server
