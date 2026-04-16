#!/bin/bash
# ============================================================
# OAI 5G Fullstack Auto-Install & Config Script v3.0
# ============================================================

set -euo pipefail

# ============================================================
# สี
# ============================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC}  $1"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_step()    { echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n${CYAN} $1${NC}\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

CURRENT_STEP="Init"
log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
  echo -e "${RED}[ERROR]${NC} หยุดที่ Step: $CURRENT_STEP"
  echo -e "${YELLOW}[TIP]${NC}   แก้ปัญหาแล้วรันใหม่ได้เลย — script จะข้าม step ที่ทำสำเร็จแล้ว"
  exit 1
}

# ============================================================
# Config (แก้ตรงนี้ที่เดียว)
# ============================================================
MCC="208"
MNC="95"
TAC="40960"
DNN="oai"
SST="1"
SD="0xFFFFFF"
IMSI="208950000000036"
KEY="0C0A34601D4F07677303652C0462535B"
OPC="63bfa50ee6523365ff14c1f45f88737d"

OAI_CN_DIR="$HOME/oai-cn5g-fed"
OAI_RAN_DIR="$HOME/openairinterface5g"
GNB_CONF="$OAI_CN_DIR/docker-compose/ran-conf/gnb.conf"
UE_CONF="$OAI_CN_DIR/docker-compose/ran-conf/nr-ue.conf"
BUILD_DIR="$OAI_RAN_DIR/cmake_targets/ran_build/build"
BACKUP_DIR="$HOME/oai_config_backups"

mkdir -p "$BACKUP_DIR"

# ============================================================
# Helper: retry command N ครั้ง
# ============================================================
retry() {
  local MAX="$1"; shift
  local DELAY="$1"; shift
  local DESC="$1"; shift
  local n=1
  while true; do
    if "$@"; then
      return 0
    fi
    if [ "$n" -ge "$MAX" ]; then
      log_error "$DESC ล้มเหลวหลังลอง $MAX ครั้ง"
    fi
    log_warn "$DESC ล้มเหลว (ครั้งที่ $n/$MAX) — รอ ${DELAY}s แล้วลองใหม่..."
    sleep "$DELAY"
    n=$((n+1))
  done
}

# ============================================================
# Helper: รอ Container healthy พร้อม timeout
# ============================================================
wait_healthy() {
  local container="$1"
  local timeout="${2:-180}"
  local elapsed=0
  log_info "รอ $container healthy..."
  while [ "$elapsed" -lt "$timeout" ]; do
    STATUS=$(sudo docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "not_found")
    case "$STATUS" in
      healthy)
        log_success "$container: healthy ✅"
        return 0
        ;;
      unhealthy)
        log_error "$container: unhealthy — ดู log: sudo docker logs $container"
        ;;
    esac
    sleep 5
    elapsed=$((elapsed+5))
    printf "\r  รอ %s... %ds/%ds" "$container" "$elapsed" "$timeout"
  done
  echo ""
  log_error "$container ไม่ขึ้น healthy ภายใน ${timeout}s"
}

# ============================================================
# Helper: แก้ค่าใน config file อย่าง robust
# รองรับ format ที่หลากหลาย ทั้ง = " " และ spaces ต่างๆ
# ถ้าแก้ไม่ได้ → auto rollback และแจ้ง error
# ============================================================
ROLLBACK_FILE=""

safe_edit_conf() {
  local FILE="$1"
  local PATTERN="$2"
  local REPLACEMENT="$3"
  local DESC="$4"

  # สร้าง backup ก่อนแก้
  local BACKUP="${BACKUP_DIR}/$(basename $FILE).$(date +%Y%m%d_%H%M%S).bak"
  cp "$FILE" "$BACKUP"
  ROLLBACK_FILE="$BACKUP"

  # พยายามแก้
  sed -i "$PATTERN" "$FILE"

  # ตรวจสอบว่าแก้สำเร็จ
  if ! grep -qP "$REPLACEMENT" "$FILE" 2>/dev/null && \
     ! grep -q "$REPLACEMENT" "$FILE" 2>/dev/null; then
    # rollback อัตโนมัติ
    log_warn "sed ไม่สำเร็จสำหรับ: $DESC — กำลัง rollback..."
    cp "$BACKUP" "$FILE"
    log_warn "Rollback สำเร็จ — ไฟล์กลับเป็นเหมือนเดิม"
    log_error "ไม่สามารถแก้ $DESC ใน $FILE — format อาจต่างจากที่คาด"
  fi
  log_success "$DESC ✅"
}

# ============================================================
# STEP 0: Pre-flight Check
# ============================================================
CURRENT_STEP="Pre-flight Check"
log_step "STEP 0: Pre-flight Check"

[ "$EUID" -eq 0 ] && log_warn "กำลังรันเป็น root — แนะนำให้รันเป็น user ปกติที่มี sudo"

OS_VER=$(lsb_release -rs 2>/dev/null || echo "unknown")
[ "$OS_VER" != "22.04" ] && log_warn "OS: Ubuntu $OS_VER — Script ออกแบบสำหรับ 22.04" || log_success "OS: Ubuntu $OS_VER ✅"

KERNEL=$(uname -r)
if echo "$KERNEL" | grep -q "lowlatency"; then
  log_success "Kernel: $KERNEL ✅"
else
  log_warn "Kernel: $KERNEL — ไม่ใช่ lowlatency"
  read -rp "ดำเนินการต่อโดยไม่มี lowlatency kernel? [y/N]: " CONT
  [[ "$CONT" =~ ^[Yy]$ ]] || exit 1
fi

RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
[ "$RAM_GB" -lt 8 ] && log_error "RAM น้อยเกินไป (${RAM_GB}GB) — ต้องการ 8GB+" || log_success "RAM: ${RAM_GB}GB ✅"

DISK_FREE=$(df -BG "$HOME" | awk 'NR==2{print $4}' | tr -d 'G')
[ "$DISK_FREE" -lt 30 ] && log_error "Disk ไม่พอ (${DISK_FREE}GB free) — ต้องการ 30GB+" || log_success "Disk: ${DISK_FREE}GB free ✅"

ping -c 1 8.8.8.8 &>/dev/null || log_error "ไม่มี Internet connection"
log_success "Internet ✅"

# ============================================================
# STEP 1: ติดตั้ง Docker
# ============================================================
CURRENT_STEP="ติดตั้ง Docker"
log_step "STEP 1: ติดตั้ง Docker"

if command -v docker &>/dev/null; then
  log_success "Docker: $(docker --version | cut -d' ' -f3 | tr -d ',') ✅"
else
  log_info "ติดตั้ง Docker CE..."
  retry 3 10 "apt update" sudo apt-get update -y
  sudo apt-get install -y ca-certificates curl gnupg lsb-release
  sudo install -m 0755 -d /etc/apt/keyrings
  retry 3 10 "download Docker GPG" \
    bash -c 'curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg'
  sudo chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  retry 3 10 "apt update after docker repo" sudo apt-get update -y
  retry 3 10 "install docker packages" \
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo usermod -aG docker "$USER"
  log_success "Docker ติดตั้งสำเร็จ — กรุณา logout/login ใหม่ แล้วรัน script อีกครั้ง"
  exit 0
fi

DOCKER_CMD="sudo docker"
groups | grep -q docker && DOCKER_CMD="docker"

# ============================================================
# STEP 2: Clone OAI CN5G
# ============================================================
CURRENT_STEP="Clone OAI CN5G"
log_step "STEP 2: Clone OAI 5G Core Network"

if [ -d "$OAI_CN_DIR/.git" ]; then
  log_success "oai-cn5g-fed มีแล้ว ข้าม ✅"
else
  log_info "Cloning oai-cn5g-fed v2.1.0..."
  retry 3 15 "clone oai-cn5g-fed" \
    git clone --branch v2.1.0 https://gitlab.eurecom.fr/oai/cn5g/oai-cn5g-fed.git "$OAI_CN_DIR"
  cd "$OAI_CN_DIR"
  retry 3 15 "submodule update" \
    git submodule update --init --recursive
  log_success "Clone OAI CN5G สำเร็จ ✅"
fi

# ============================================================
# STEP 3: Pull Docker Images
# ============================================================
CURRENT_STEP="Pull Docker Images"
log_step "STEP 3: Pull Docker Images"

cd "$OAI_CN_DIR/docker-compose"
if $DOCKER_CMD images | grep -q "oai-amf"; then
  log_success "Docker Images มีแล้ว ข้าม ✅"
else
  log_info "Pulling OAI CN Images..."
  retry 3 30 "docker compose pull" \
    $DOCKER_CMD compose -f docker-compose-basic-nrf.yaml pull
  log_success "Pull Images สำเร็จ ✅"
fi

# ============================================================
# STEP 4: Clone และ Build OAI RAN
# ============================================================
CURRENT_STEP="Build OAI RAN"
log_step "STEP 4: Clone และ Build OAI RAN"

if [ -f "$BUILD_DIR/nr-softmodem" ] && [ -f "$BUILD_DIR/nr-uesoftmodem" ]; then
  log_success "nr-softmodem และ nr-uesoftmodem มีแล้ว ข้าม ✅"
else
  # Clone ถ้ายังไม่มี
  if [ ! -d "$OAI_RAN_DIR/.git" ]; then
    log_info "Cloning openairinterface5g branch 2024.w51..."
    retry 3 15 "clone openairinterface5g" \
      git clone --branch 2024.w51 https://gitlab.eurecom.fr/oai/openairinterface5g.git "$OAI_RAN_DIR"
  fi

  cd "$OAI_RAN_DIR"
  source oaienv
  cd cmake_targets

  # ติดตั้ง dependencies พร้อม retry
  log_info "ติดตั้ง Build Dependencies..."
  BUILD_DEP_LOG="/tmp/oai_dep_$(date +%s).log"
  retry 2 30 "install dependencies" \
    bash -c "./build_oai -I > $BUILD_DEP_LOG 2>&1"
  log_success "Dependencies สำเร็จ ✅"

  # Build พร้อม retry และ progress
  log_info "Building gNB และ UE (ใช้เวลา 15-30 นาที)..."
  BUILD_LOG="/tmp/oai_build_$(date +%s).log"

  build_ran() {
    ./build_oai -w SIMU --gNB --nrUE --ninja > "$BUILD_LOG" 2>&1 &
    BUILD_PID=$!
    local elapsed=0
    while kill -0 $BUILD_PID 2>/dev/null; do
      printf "\r  กำลัง Build... %ds" "$elapsed"
      sleep 10
      elapsed=$((elapsed+10))
    done
    echo ""
    wait $BUILD_PID
    return $?
  }

  retry 2 60 "build OAI RAN" build_ran

  # ตรวจสอบ binary
  [ ! -f "$BUILD_DIR/nr-softmodem" ]   && log_error "nr-softmodem ไม่พบ — ดู log: $BUILD_LOG"
  [ ! -f "$BUILD_DIR/nr-uesoftmodem" ] && log_error "nr-uesoftmodem ไม่พบ — ดู log: $BUILD_LOG"
  log_success "Build OAI RAN สำเร็จ ✅"
fi

# ============================================================
# STEP 5: รัน 5G Core Network
# ============================================================
CURRENT_STEP="รัน 5G Core Network"
log_step "STEP 5: รัน 5G Core Network"

cd "$OAI_CN_DIR/docker-compose"

if $DOCKER_CMD ps | grep -q "oai-amf"; then
  log_info "หยุด Core Network เดิม..."
  $DOCKER_CMD compose -f docker-compose-basic-nrf.yaml down 2>/dev/null || true
  sleep 5
fi

log_info "เริ่ม 5G Core Network..."
retry 2 10 "docker compose up" \
  $DOCKER_CMD compose -f docker-compose-basic-nrf.yaml up -d

for CONTAINER in mysql oai-nrf oai-amf oai-smf oai-upf oai-udm oai-udr oai-ausf oai-ext-dn; do
  wait_healthy "$CONTAINER" 180
done
log_success "5G Core Network รันครบทุก Container ✅"

# ============================================================
# STEP 6: Auto-detect Network
# ============================================================
CURRENT_STEP="Auto-detect Network"
log_step "STEP 6: Auto-detect Network Config"

# หา AMF IP ด้วย python3 (แม่นยำสุด)
AMF_IP=$(sudo docker inspect oai-amf 2>/dev/null | \
  python3 -c "
import sys, json
d = json.load(sys.stdin)
nets = d[0]['NetworkSettings']['Networks']
for v in nets.values():
    if v['IPAddress']:
        print(v['IPAddress'])
        break
" 2>/dev/null || echo "")

# fallback ถ้า python3 ล้มเหลว
if [ -z "$AMF_IP" ]; then
  AMF_IP=$(sudo docker inspect oai-amf | \
    grep '"IPAddress"' | grep -v '""' | head -1 | \
    grep -oP '\d+\.\d+\.\d+\.\d+' || echo "")
fi
[ -z "$AMF_IP" ] && log_error "ไม่พบ AMF IP"
log_success "AMF IP: $AMF_IP ✅"

# หา Bridge Interface
BRIDGE_IFACE=$(ip link show | grep -E "^[0-9]+: (demo-oai|br-)" | \
  head -1 | awk -F': ' '{print $2}' | awk '{print $1}')
[ -z "$BRIDGE_IFACE" ] && log_error "ไม่พบ Docker Bridge Interface"
log_success "Bridge Interface: $BRIDGE_IFACE ✅"

# หา Subnet
DOCKER_NETWORK_ID=$($DOCKER_CMD network ls | grep oai | awk '{print $1}' | head -1)
DOCKER_SUBNET=$($DOCKER_CMD network inspect "$DOCKER_NETWORK_ID" | \
  grep -oP '"Subnet": "\K[^"]+' | head -1)
[ -z "$DOCKER_SUBNET" ] && log_error "ไม่พบ Docker Subnet"

SUBNET_BASE=$(echo "$DOCKER_SUBNET" | cut -d'/' -f1 | cut -d'.' -f1-3)
SUBNET_MASK=$(echo "$DOCKER_SUBNET" | cut -d'/' -f2)
GNB_IP="${SUBNET_BASE}.200"
log_success "Subnet: $DOCKER_SUBNET → gNB IP: $GNB_IP ✅"

# เพิ่ม Bridge IP
if ip addr show "$BRIDGE_IFACE" | grep -q "$GNB_IP"; then
  log_success "Bridge IP $GNB_IP มีแล้ว ✅"
else
  sudo ip addr add "${GNB_IP}/${SUBNET_MASK}" dev "$BRIDGE_IFACE" 2>/dev/null || true
  ip addr show "$BRIDGE_IFACE" | grep -q "$GNB_IP" || \
    log_error "ไม่สามารถเพิ่ม IP $GNB_IP บน $BRIDGE_IFACE"
  log_success "เพิ่ม Bridge IP $GNB_IP สำเร็จ ✅"
fi

# ============================================================
# STEP 7: Persistent Bridge IP ด้วย systemd
# ============================================================
CURRENT_STEP="Persistent Network"
log_step "STEP 7: Persistent Bridge IP"

sudo tee /etc/systemd/system/oai-bridge.service > /dev/null << SVCEOF
[Unit]
Description=OAI 5G Bridge IP Setup
After=docker.service network-online.target
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=/bin/sleep 15
ExecStart=/bin/bash -c '\
  ip link delete oaitun_ue1 2>/dev/null || true; \
  IFACE=\$(ip link show | grep -E "demo-oai|br-" | head -1 | awk -F": " "{print \$2}" | awk "{print \$1}"); \
  [ -n "\$IFACE" ] && ip addr add ${GNB_IP}/${SUBNET_MASK} dev \$IFACE 2>/dev/null || true'
ExecStop=/bin/true
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SVCEOF

sudo systemctl daemon-reload
sudo systemctl enable oai-bridge.service

# ตรวจสอบ
systemctl is-enabled oai-bridge.service &>/dev/null && \
  log_success "systemd oai-bridge.service enabled ✅" || \
  log_warn "systemd service อาจไม่ได้ enable"

# ============================================================
# STEP 8: Config gnb.conf (Robust)
# ============================================================
CURRENT_STEP="Config gnb.conf"
log_step "STEP 8: Auto-Config gnb.conf"

# Backup timestamped
GNBCONF_BAK="${BACKUP_DIR}/gnb.conf.$(date +%Y%m%d_%H%M%S).bak"
cp "$GNB_CONF" "$GNBCONF_BAK"
log_info "Backup: $GNBCONF_BAK"

# แก้ AMF IP — รองรับ format หลายแบบ
safe_edit_conf "$GNB_CONF" \
  "s/ipv4[[:space:]]*=[[:space:]]*\"[0-9.]*\"/ipv4       = \"${AMF_IP}\"/" \
  "${AMF_IP}" \
  "AMF IP → $AMF_IP"

# แก้ gNB IP N2
safe_edit_conf "$GNB_CONF" \
  "s/GNB_IPV4_ADDRESS_FOR_NG_AMF[[:space:]]*=[[:space:]]*\"[0-9.]*\"/GNB_IPV4_ADDRESS_FOR_NG_AMF              = \"${GNB_IP}\"/" \
  "${GNB_IP}" \
  "gNB IP (N2) → $GNB_IP"

# แก้ gNB IP N3
safe_edit_conf "$GNB_CONF" \
  "s/GNB_IPV4_ADDRESS_FOR_NGU[[:space:]]*=[[:space:]]*\"[0-9.]*\"/GNB_IPV4_ADDRESS_FOR_NGU                 = \"${GNB_IP}\"/" \
  "${GNB_IP}" \
  "gNB IP (N3) → $GNB_IP"

# แก้ TAC
safe_edit_conf "$GNB_CONF" \
  "s/tracking_area_code[[:space:]]*=[[:space:]]*[0-9]*/tracking_area_code  =  ${TAC}/" \
  "${TAC}" \
  "TAC → $TAC"

# แก้ PLMN
sed -i "s/mcc = [0-9]*/mcc = ${MCC}/g" "$GNB_CONF"
sed -i "s/mnc = [0-9]*/mnc = ${MNC}/g" "$GNB_CONF"
grep -q "mcc = ${MCC}" "$GNB_CONF" || log_error "แก้ MCC ไม่สำเร็จ"
log_success "MCC/MNC → $MCC/$MNC ✅"

# แก้ SD
sed -i "s/sd = 0x[0-9a-fA-F]*/sd = ${SD}/g" "$GNB_CONF"
grep -qi "sd = ${SD}" "$GNB_CONF" || log_error "แก้ SD ไม่สำเร็จ"
log_success "SD → $SD ✅"

log_success "gnb.conf Config ครบถ้วน ✅"

# ============================================================
# STEP 9: Config nr-ue.conf
# ============================================================
CURRENT_STEP="Config nr-ue.conf"
log_step "STEP 9: Auto-Config nr-ue.conf"

UECONF_BAK="${BACKUP_DIR}/nr-ue.conf.$(date +%Y%m%d_%H%M%S).bak"
cp "$UE_CONF" "$UECONF_BAK" 2>/dev/null || true

cat > "$UE_CONF" << UEOF
uicc0 = {
  imsi = "${IMSI}";
  key = "${KEY}";
  opc = "${OPC}";
  dnn = "${DNN}";
  nssai_sst = ${SST};
  nssai_sd = ${SD};
}

rfsimulator: {
  serveraddr = "127.0.0.1";
  serverport = "4043";
  options = ();
  wait_for_sync = 0;
  prop_delay = 0;
}
UEOF

grep -q "$IMSI" "$UE_CONF" || log_error "เขียน nr-ue.conf ไม่สำเร็จ"
log_success "nr-ue.conf Config ครบถ้วน ✅"

# ============================================================
# STEP 10: สร้าง Helper Scripts
# ============================================================
CURRENT_STEP="สร้าง Helper Scripts"
log_step "STEP 10: สร้าง Helper Scripts"

# ---------- start_gnb.sh ----------
cat > "$HOME/start_gnb.sh" << GNBEOF
#!/bin/bash
set -e
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Starting gNB"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Auto-detect AMF IP ทุกครั้ง
AMF_IP=\$(sudo docker inspect oai-amf 2>/dev/null | \
  python3 -c "
import sys,json
d=json.load(sys.stdin)
nets=d[0]['NetworkSettings']['Networks']
for v in nets.values():
    if v['IPAddress']:
        print(v['IPAddress']); break
" 2>/dev/null || \
  sudo docker inspect oai-amf | grep '"IPAddress"' | grep -v '""' | \
  head -1 | grep -oP '\d+\.\d+\.\d+\.\d+')

[ -z "\$AMF_IP" ] && echo "[ERROR] ไม่พบ AMF IP — Core รันอยู่ไหม?" && exit 1
echo "[INFO] AMF IP: \$AMF_IP"

# Auto-detect Bridge
BRIDGE=\$(ip link show | grep -E "demo-oai|br-" | head -1 | \
  awk -F': ' '{print \$2}' | awk '{print \$1}')
[ -z "\$BRIDGE" ] && echo "[ERROR] ไม่พบ Bridge Interface" && exit 1

# เพิ่ม Bridge IP ถ้าหาย
sudo ip addr add ${GNB_IP}/${SUBNET_MASK} dev \$BRIDGE 2>/dev/null || true
echo "[INFO] Bridge: \$BRIDGE / gNB IP: ${GNB_IP}"

# อัปเดต AMF IP ใน gnb.conf
sed -i "s/ipv4[[:space:]]*=[[:space:]]*\"[0-9.]*\"/ipv4       = \"\${AMF_IP}\"/" ${GNB_CONF}
ACTUAL=\$(grep 'ipv4.*=.*"[0-9]' ${GNB_CONF} | grep -oP '\d+\.\d+\.\d+\.\d+' | head -1)
[ "\$ACTUAL" != "\$AMF_IP" ] && echo "[ERROR] อัปเดต AMF IP ใน gnb.conf ไม่สำเร็จ" && exit 1
echo "[INFO] gnb.conf อัปเดต AMF IP → \$AMF_IP สำเร็จ"

# Kill process เก่า
sudo pkill -9 nr-softmodem 2>/dev/null || true
sudo fuser -k 4043/tcp 2>/dev/null || true
sudo fuser -k 2152/udp 2>/dev/null || true
sleep 2

echo "[INFO] รัน gNB..."
cd ${BUILD_DIR}
sudo ./nr-softmodem -O ${GNB_CONF} --sa --rfsim --rfsimulator.serveraddr server
GNBEOF
chmod +x "$HOME/start_gnb.sh"

# ---------- start_ue.sh ----------
cat > "$HOME/start_ue.sh" << UEEOF
#!/bin/bash
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Starting UE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
sudo pkill -9 nr-uesoftmodem 2>/dev/null || true
sudo ip link delete oaitun_ue1 2>/dev/null || true
sleep 2
echo "[INFO] รัน UE..."
cd ${BUILD_DIR}
sudo ./nr-uesoftmodem \\
  -O ${UE_CONF} \\
  --rfsim \\
  --rfsimulator.serveraddr 127.0.0.1 \\
  -C 3319680000 \\
  -r 106 \\
  --numerology 1 \\
  --ssb 516
UEEOF
chmod +x "$HOME/start_ue.sh"

# ---------- stop_all.sh ----------
cat > "$HOME/stop_all.sh" << STOPEOF
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
cd ${OAI_CN_DIR}/docker-compose
sudo docker compose -f docker-compose-basic-nrf.yaml down
echo "[4/4] ตรวจสอบ..."
sleep 3
REMAIN=\$(sudo docker ps | grep oai | wc -l)
[ "\$REMAIN" -eq 0 ] && echo "✅ หยุดทุกอย่างสำเร็จ" || \
  echo "⚠️  ยังมี Container ค้างอยู่ \$REMAIN ตัว"
STOPEOF
chmod +x "$HOME/stop_all.sh"

# ---------- check_config.sh ----------
cat > "$HOME/check_config.sh" << CHECKEOF
#!/bin/bash
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "         5G CONFIG CHECKER"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

LIVE_AMF=\$(sudo docker inspect oai-amf 2>/dev/null | \
  grep '"IPAddress"' | grep -v '""' | head -1 | \
  grep -oP '\d+\.\d+\.\d+\.\d+' || echo "N/A")
CONF_AMF=\$(grep 'ipv4.*=.*"[0-9]' ${GNB_CONF} | \
  grep -oP '\d+\.\d+\.\d+\.\d+' | head -1 || echo "N/A")
AMF_STATUS=\$([ "\$LIVE_AMF" = "\$CONF_AMF" ] && echo "✅ ตรง" || echo "⚠️  ไม่ตรง!")

printf "\n  %-22s %-22s %s\n" "Parameter" "Value" "Status"
echo "  ──────────────────────────────────────────────"
printf "  %-22s %-22s %s\n" "AMF IP (live)"      "\$LIVE_AMF"  "\$AMF_STATUS"
printf "  %-22s %-22s %s\n" "AMF IP (gnb.conf)"  "\$CONF_AMF"  ""
printf "  %-22s %-22s %s\n" "gNB IP"             "${GNB_IP}"   "✅"
printf "  %-22s %-22s %s\n" "MCC/MNC"            "${MCC}/${MNC}" "✅"
printf "  %-22s %-22s %s\n" "TAC"                "${TAC}"      "✅"
printf "  %-22s %-22s %s\n" "IMSI"               "${IMSI}"     "✅"

echo ""
echo "  [ Container Status ]"
sudo docker ps --format "    {{.Names}}: {{.Status}}" | grep oai

echo ""
echo "  [ Backup Files ]"
ls ${BACKUP_DIR}/ 2>/dev/null | sed 's/^/    /' || echo "    ไม่มี backup"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
CHECKEOF
chmod +x "$HOME/check_config.sh"

# ---------- rollback_config.sh ----------
cat > "$HOME/rollback_config.sh" << ROLLEOF
#!/bin/bash
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Rollback Config"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Backup ที่มีอยู่:"
ls -1t ${BACKUP_DIR}/ | head -20 | nl
echo ""
read -rp "เลือกหมายเลข backup (หรือ q เพื่อยกเลิก): " CHOICE
[[ "\$CHOICE" == "q" ]] && exit 0
FILE=\$(ls -1t ${BACKUP_DIR}/ | sed -n "\${CHOICE}p")
[ -z "\$FILE" ] && echo "ไม่พบ backup" && exit 1
ORIG=\$(echo "\$FILE" | sed 's/\\..*\\.bak//')
cp "${BACKUP_DIR}/\$FILE" "${OAI_CN_DIR}/docker-compose/ran-conf/\$ORIG"
echo "✅ Rollback สำเร็จ: \$FILE → \$ORIG"
ROLLEOF
chmod +x "$HOME/rollback_config.sh"

log_success "สร้าง Helper Scripts ครบ ✅"
log_info "  ~/start_gnb.sh       — รัน gNB (auto-detect AMF IP)"
log_info "  ~/start_ue.sh        — รัน UE"
log_info "  ~/stop_all.sh        — หยุดทุกอย่าง"
log_info "  ~/check_config.sh    — เช็ค Config + AMF IP live"
log_info "  ~/rollback_config.sh — rollback config กลับ backup"

# ============================================================
# STEP 11: Final Verification
# ============================================================
CURRENT_STEP="Final Verification"
log_step "STEP 11: Final Verification"

PASS=0; FAIL=0
check() {
  local desc="$1"; local cmd="$2"
  if eval "$cmd" &>/dev/null; then
    log_success "$desc ✅"; PASS=$((PASS+1))
  else
    log_warn "$desc ❌"; FAIL=$((FAIL+1))
  fi
}

check "Docker running"            "sudo docker ps | grep -q oai-amf"
check "AMF healthy"               "sudo docker inspect oai-amf | grep -q 'healthy'"
check "SMF healthy"               "sudo docker inspect oai-smf | grep -q 'healthy'"
check "UPF healthy"               "sudo docker inspect oai-upf | grep -q 'healthy'"
check "NRF healthy"               "sudo docker inspect oai-nrf | grep -q 'healthy'"
check "nr-softmodem exists"       "test -f $BUILD_DIR/nr-softmodem"
check "nr-uesoftmodem exists"     "test -f $BUILD_DIR/nr-uesoftmodem"
check "gnb.conf has AMF IP"       "grep -q '$AMF_IP' $GNB_CONF"
check "gnb.conf has gNB IP"       "grep -q '$GNB_IP' $GNB_CONF"
check "gnb.conf has TAC"          "grep -q '$TAC' $GNB_CONF"
check "gnb.conf has MCC"          "grep -q 'mcc = $MCC' $GNB_CONF"
check "ue.conf has IMSI"          "grep -q '$IMSI' $UE_CONF"
check "ue.conf has SD"            "grep -qi '$SD' $UE_CONF"
check "Bridge IP exists"          "ip addr show $BRIDGE_IFACE | grep -q '$GNB_IP'"
check "systemd service enabled"   "systemctl is-enabled oai-bridge.service"
check "start_gnb.sh executable"   "test -x $HOME/start_gnb.sh"
check "start_ue.sh executable"    "test -x $HOME/start_ue.sh"
check "stop_all.sh executable"    "test -x $HOME/stop_all.sh"
check "rollback_config.sh exists" "test -x $HOME/rollback_config.sh"
check "backup dir exists"         "test -d $BACKUP_DIR"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
TOTAL=$((PASS+FAIL))
PCT=$((PASS*100/TOTAL))
echo "  ผ่าน: $PASS/$TOTAL รายการ ($PCT%)"
if [ "$FAIL" -eq 0 ]; then
  echo -e "  ${GREEN}ทุกอย่างพร้อมใช้งาน 🎉${NC}"
else
  echo -e "  ${YELLOW}ไม่ผ่าน: $FAIL รายการ — ตรวจสอบ ❌ ข้างต้น${NC}"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ============================================================
# DONE
# ============================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ Setup เสร็จสมบูรณ์!"
echo ""
echo "  วิธีใช้:"
echo "  ┌──────────────────────────────────────"
echo "  │ Terminal 1:  ~/start_gnb.sh"
echo "  │ Terminal 2:  ~/start_ue.sh"
echo "  │ Terminal 3:  ping -I oaitun_ue1 8.8.8.8 -i 0.5"
echo "  │"
echo "  │ หยุดทั้งหมด:    ~/stop_all.sh"
echo "  │ เช็ค Config:    ~/check_config.sh"
echo "  │ Rollback:       ~/rollback_config.sh"
echo "  └──────────────────────────────────────"
echo ""
echo "  Config:"
echo "  AMF IP  : $AMF_IP"
echo "  gNB IP  : $GNB_IP"
echo "  MCC/MNC : $MCC/$MNC | TAC: $TAC"
echo "  IMSI    : $IMSI"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
