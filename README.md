
<img width="668" height="803" alt="image" src="https://github.com/user-attachments/assets/948367df-556b-454b-ab87-2cb58cdf02dd" />

# 📡 OAI 5G Fullstack Auto Setup Script

Automated script for deploying a complete **OpenAirInterface (OAI) 5G Standalone (SA)** environment including Core Network, gNB, and UE.

> ⚡ One command → Full 5G stack ready to use

---

## ✨ Features

- 🚀 One-command full deployment (Core + RAN + UE)
- 🔁 Built-in retry system (network-safe)
- 🧠 Auto-detect AMF IP, subnet, and network interfaces
- 🛡️ Safe config editing with auto-backup & rollback
- 📦 Docker-based Core Network
- 🔧 Auto-generated management scripts
- 📊 Health check & verification system
- 🔌 Persistent network config (systemd)

---

## 🖥️ Requirements

- Ubuntu 22.04
- RAM ≥ 8 GB
- Disk ≥ 30 GB free
- Internet connection
- (Optional) Low latency kernel

---

## ⚙️ Quick Start

```bash
git clone https://github.com/patraratorn/OAI-Automation-Scripts
cd OAI-Automation-Scripts
chmod +x oai_setup_V3.sh
./oai_setup_V3.sh
```
## ⚙️ Configuration
Edit parameters at the top of the script
```bash
MCC="208"
MNC="95"
TAC="40960"
DNN="oai"
SST="1"
SD="0xFFFFFF"
IMSI="208950000000036"
KEY="..."
OPC="..."
```
## 🧩 Workflow
```bash
Pre-check → Install Docker → Clone CN → Pull Images → Build RAN
→ Start Core → Auto Network Config → Configure gNB/UE → Validate
```

## ▶️ Usage
Start system
```bash
##terminal1
./start_gnb.sh
##terminal2
./start_ue.sh
```

## Test connectivity
```bash
ping -I oaitun_ue1 8.8.8.8
```
## Stop system
```bash
./stop_all.sh
```
## Check system
```bash
./check_config.sh
```
## Rollback config
```bash
./rollback_config.sh
```
## 📂 Project Structure
```bash
.
├── oai_setup_V3.sh
├── start_gnb.sh
├── start_ue.sh
├── stop_all.sh
├── check_config.sh
├── rollback_config.sh
└── oai_config_backups/
```
## 🛠️ Troubleshooting
Docker issue
```bash
logout
# login again
./oai_setup_V3.sh
```
## Container not healthy
```bash
docker logs <container>
💾 Backup
```

## All configs are automatically backed up:
```bash
~/oai_config_backups/
```

## 📌 Notes
Uses RF Simulator (no SDR hardware required)
Script is idempotent (safe to re-run)
Designed for lab / research / learning environments
