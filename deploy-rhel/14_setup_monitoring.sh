#!/bin/bash
# 設定監控 (sar + 簡單告警)
set -euo pipefail
PORTAL="${SF_PORTAL_ROOT:-/opt/portal}"
ALERT_MAIL="${SF_ALERT_MAIL:-it-admin@corp.local}"

echo "=== 設定監控 ==="

dnf install -y sysstat mailx 2>&1 | tail -3
systemctl enable --now sysstat

# 監控腳本 (對應 Windows SF_Monitoring_Check task)
cat > "$PORTAL/scripts/monitoring_check.sh" <<EOF
#!/bin/bash
# SF Monitoring Check (每 5 分鐘跑)
ALERTS=()

# CPU
CPU=\$(top -bn1 | grep '%Cpu' | awk '{print 100-\$8}')
(( \$(echo "\$CPU > 80" | bc -l) )) && ALERTS+=("CPU: \$CPU%")

# Memory
MEM=\$(free | grep Mem | awk '{print \$3/\$2 * 100}')
(( \$(echo "\$MEM > 90" | bc -l) )) && ALERTS+=("Memory: \$MEM%")

# Disk
DISK=\$(df / | awk 'NR==2{gsub(/%/,"");print \$5}')
(( DISK > 80 )) && ALERTS+=("Disk /: \${DISK}%")

# Services
for svc in sshd nginx postgresql sf-portal; do
    systemctl is-active \$svc &>/dev/null || ALERTS+=("Service \$svc: DOWN")
done

# 寄信
if [ \${#ALERTS[@]} -gt 0 ]; then
    {
        echo "SF 主機告警 (\$(hostname))"
        echo ""
        printf '  - %s\n' "\${ALERTS[@]}"
    } | mail -s "[SF Alert] \$(hostname) \$(date +%F)" $ALERT_MAIL
fi
EOF
chmod +x "$PORTAL/scripts/monitoring_check.sh"

# cron 每 5 分鐘
cat > /etc/cron.d/sf-monitoring <<EOF
*/5 * * * * root $PORTAL/scripts/monitoring_check.sh
EOF

echo "[ok] 監控設定 (告警送 $ALERT_MAIL)"
