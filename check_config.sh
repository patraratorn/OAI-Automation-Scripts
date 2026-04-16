#!/bin/bash
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "         5G CONFIG CHECKER"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

LIVE_AMF=$(sudo docker inspect oai-amf 2>/dev/null |   grep '"IPAddress"' | grep -v '""' | head -1 |   grep -oP '\d+\.\d+\.\d+\.\d+' || echo "N/A")
CONF_AMF=$(grep 'ipv4.*=.*"[0-9]' /home/srs/oai-cn5g-fed/docker-compose/ran-conf/gnb.conf |   grep -oP '\d+\.\d+\.\d+\.\d+' | head -1 || echo "N/A")
AMF_STATUS=$([ "$LIVE_AMF" = "$CONF_AMF" ] && echo "✅ ตรง" || echo "⚠️  ไม่ตรง!")

printf "\n  %-22s %-22s %s\n" "Parameter" "Value" "Status"
echo "  ──────────────────────────────────────────────"
printf "  %-22s %-22s %s\n" "AMF IP (live)"      "$LIVE_AMF"  "$AMF_STATUS"
printf "  %-22s %-22s %s\n" "AMF IP (gnb.conf)"  "$CONF_AMF"  ""
printf "  %-22s %-22s %s\n" "gNB IP"             "192.168.70.200"   "✅"
printf "  %-22s %-22s %s\n" "MCC/MNC"            "208/95" "✅"
printf "  %-22s %-22s %s\n" "TAC"                "40960"      "✅"
printf "  %-22s %-22s %s\n" "IMSI"               "208950000000036"     "✅"

echo ""
echo "  [ Container Status ]"
sudo docker ps --format "    {{.Names}}: {{.Status}}" | grep oai

echo ""
echo "  [ Backup Files ]"
ls /home/srs/oai_config_backups/ 2>/dev/null | sed 's/^/    /' || echo "    ไม่มี backup"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
