#!/bin/bash
# 設定 chrony (取代 W32Time)
set -euo pipefail
NTP_SERVERS="${SF_NTP_SERVERS:-ntp1.corp.local ntp2.corp.local}"
echo "=== 設定 chrony ==="
dnf install -y chrony 2>&1 | tail -3
# 改 chrony.conf 用公司 NTP
sed -i '/^pool /d' /etc/chrony.conf
sed -i '/^server /d' /etc/chrony.conf
for srv in $NTP_SERVERS; do
    echo "server $srv iburst" >> /etc/chrony.conf
done
systemctl enable --now chronyd
sleep 2
chronyc sources -v 2>&1 | head -10
echo "[ok] chrony 設定"
