#!/bin/bash
# 設定集中 log + auditd (對齊主管圖稽核要求)
set -euo pipefail
echo "=== 設定 logging + auditd ==="

# auditd 監控 D:\DataExchange (對應 Windows SACL)
dnf install -y audit 2>&1 | tail -3
systemctl enable --now auditd

DATA="${SF_DATA_ROOT:-/data/exchange}"
auditctl -w "$DATA" -p wa -k sf_file_exchange 2>/dev/null || true
echo "-w $DATA -p wa -k sf_file_exchange" >> /etc/audit/rules.d/sf.rules

# rsyslog 集中 (預留 SIEM 接, 第二階段)
SIEM="${SF_SIEM_SERVER:-}"
if [[ -n "$SIEM" ]]; then
    cat > /etc/rsyslog.d/99-siem-forward.conf <<EOF
*.* @@${SIEM}:514
EOF
    systemctl restart rsyslog
    echo "[ok] rsyslog forward to $SIEM"
else
    echo "[skip] SIEM 未設, 跳過 syslog forward (第二階段)"
fi

echo "[ok] auditd + rsyslog"
echo "  auditctl -l 看規則"
echo "  ausearch -k sf_file_exchange 看紀錄"
