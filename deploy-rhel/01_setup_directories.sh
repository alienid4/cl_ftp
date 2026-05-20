#!/bin/bash
# 建立 SF 主機目錄結構
# 對應 Windows: deploy/01_setup_directories.ps1
set -euo pipefail

DATA="${SF_DATA_ROOT:-/data/exchange}"
PORTAL="${SF_PORTAL_ROOT:-/opt/portal}"
DEPTS=(${SF_DEPTS:-HR FIN OPS})

echo "=== 建立目錄結構 ==="
echo "DataRoot:   $DATA"
echo "PortalRoot: $PORTAL"

# 業務檔目錄
mkdir -p "$DATA"/{HR,FIN,OPS}/{inbound,pending,outbound,archive,error}
for d in "${DEPTS[@]}"; do
    for sub in inbound pending outbound archive error; do
        mkdir -p "$DATA/$d/$sub"
    done
done
mkdir -p "$DATA/samba"

# Portal 系統檔
mkdir -p "$PORTAL"/{app,logs,scripts,backups,ftps_pasv,venv}

# Log 目錄
mkdir -p /var/log/sf-portal

echo "[ok] 目錄結構建立完成"
tree -L 2 "$DATA" 2>/dev/null || ls -la "$DATA"
echo ""
ls -la "$PORTAL"
