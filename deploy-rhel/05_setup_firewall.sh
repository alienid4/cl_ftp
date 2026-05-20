#!/bin/bash
# 設防火牆規則 (firewalld)
# 對應 Windows: deploy/05_setup_firewall.ps1
set -euo pipefail

CORP_NET="${SF_CORP_NET:-10.0.0.0/8}"

echo "=== 設定 firewalld ==="

# 確保 firewalld 開
if ! systemctl is-active firewalld &>/dev/null; then
    systemctl enable --now firewalld
fi

# 1. 建 SF zone (限公司網段)
firewall-cmd --permanent --new-zone=sf 2>/dev/null || echo "[skip] zone sf 已存在"
firewall-cmd --permanent --zone=sf --add-source="$CORP_NET"

# 2. 允許各服務
firewall-cmd --permanent --zone=sf --add-service=ssh         # SFTP
firewall-cmd --permanent --zone=sf --add-service=https       # Portal (TLS)
firewall-cmd --permanent --zone=sf --add-port=5000/tcp       # Portal (HTTP PoC)
firewall-cmd --permanent --zone=sf --add-service=samba       # SMB share
firewall-cmd --permanent --zone=sf --add-port=3389/tcp       # 不需要, 沒 RDP

# 3. 重載
firewall-cmd --reload
echo "[ok] firewalld 規則套用 (限 $CORP_NET)"

echo ""
echo "=== 當前規則 ==="
firewall-cmd --zone=sf --list-all 2>/dev/null || firewall-cmd --list-all
