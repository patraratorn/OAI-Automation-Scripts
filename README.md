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
git clone <your-repo-url>
cd <your-repo>
chmod +x oai_setup_V3.sh
./oai_setup_V3.sh

⚠️ If Docker is installed during setup, logout/login and run again.

⚙️ Configuration

Edit parameters at the top of the script:

MCC="208"
MNC="95"
TAC="40960"
DNN="oai"
SST="1"
SD="0xFFFFFF"
IMSI="208950000000036"
KEY="..."
OPC="..."
🧩 Workflow
Pre-check → Install Docker → Clone CN → Pull Images → Build RAN
→ Start Core → Auto Network Config → Configure gNB/UE → Validate
▶️ Usage
Start system
./start_gnb.sh
./start_ue.sh
Test connectivity
ping -I oaitun_ue1 8.8.8.8
Stop system
./stop_all.sh
Check system
./check_config.sh
Rollback config
./rollback_config.sh
📂 Project Structure
.
├── oai_setup_V3.sh
├── start_gnb.sh
├── start_ue.sh
├── stop_all.sh
├── check_config.sh
├── rollback_config.sh
└── oai_config_backups/
🛠️ Troubleshooting
Docker issue
logout
# login again
./oai_setup_V3.sh
Container not healthy
docker logs <container>
💾 Backup

All configs are automatically backed up:

~/oai_config_backups/
📌 Notes
Uses RF Simulator (no SDR hardware required)
Script is idempotent (safe to re-run)
Designed for lab / research / learning environments
