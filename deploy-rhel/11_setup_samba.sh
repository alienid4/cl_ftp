#!/bin/bash
# 設定 Samba 4 (SMB share)
set -euo pipefail
DATA="${SF_DATA_ROOT:-/data/exchange}"
SKIP="${SF_SKIP_SAMBA:-0}"

if [[ "$SKIP" == "1" ]]; then echo "[skip]"; exit 0; fi

echo "=== 設定 Samba ==="
dnf install -y samba samba-common samba-client cifs-utils 2>&1 | tail -3

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "$REPO_ROOT/config/samba/smb.conf" ]]; then
    cp /etc/samba/smb.conf /etc/samba/smb.conf.bak.$(date +%Y%m%d_%H%M%S) 2>/dev/null
    cp "$REPO_ROOT/config/samba/smb.conf" /etc/samba/smb.conf
    echo "[ok] smb.conf 套用"
fi

# 建 samba 子目錄
mkdir -p "$DATA/samba"/{architecture,hr,finance,security}
chown -R root:sftp_users "$DATA/samba"
chmod -R 2770 "$DATA/samba"

# SELinux
chcon -R -t samba_share_t "$DATA/samba" 2>/dev/null || true
setsebool -P samba_export_all_rw on 2>/dev/null || true

testparm -s 2>&1 | head -5
systemctl enable --now smb nmb
firewall-cmd --permanent --zone=sf --add-service=samba 2>/dev/null || true
firewall-cmd --reload
echo "[ok] Samba $(systemctl is-active smb)"
