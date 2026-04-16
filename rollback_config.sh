#!/bin/bash
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Rollback Config"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Backup ที่มีอยู่:"
ls -1t /home/srs/oai_config_backups/ | head -20 | nl
echo ""
read -rp "เลือกหมายเลข backup (หรือ q เพื่อยกเลิก): " CHOICE
[[ "$CHOICE" == "q" ]] && exit 0
FILE=$(ls -1t /home/srs/oai_config_backups/ | sed -n "${CHOICE}p")
[ -z "$FILE" ] && echo "ไม่พบ backup" && exit 1
ORIG=$(echo "$FILE" | sed 's/\..*\.bak//')
cp "/home/srs/oai_config_backups/$FILE" "/home/srs/oai-cn5g-fed/docker-compose/ran-conf/$ORIG"
echo "✅ Rollback สำเร็จ: $FILE → $ORIG"
