#!/bin/bash
# 建立 SF 主機目錄結構 (對齊主管圖 u0X 業務代號模型)
# v2.0.0.1: 預設只建 1 個帳號目錄, 對齊使用者「PoC 先一個帳號」需求
set -euo pipefail

DATA="${SF_DATA_ROOT:-/data/exchange}"
PORTAL="${SF_PORTAL_ROOT:-/opt/portal}"
# 預設只建 u01t (PoC 測試帳號); 多帳號用空格分隔: SF_ACCOUNTS="u01 u02 u03"
ACCOUNTS=(${SF_ACCOUNTS:-u01t})

echo "=== 建立目錄結構 ==="
echo "DataRoot:   $DATA"
echo "PortalRoot: $PORTAL"
echo "Accounts:   ${ACCOUNTS[*]}"

# 業務檔目錄: 每個帳號 5 個子目錄
for a in "${ACCOUNTS[@]}"; do
    for sub in inbound pending outbound archive error; do
        mkdir -p "$DATA/$a/$sub"
    done
    echo "[ok] $DATA/$a/{inbound,pending,outbound,archive,error}"
done

# samba 部門下載區 (即使 1 帳號也建 samba 根, 之後擴展用)
mkdir -p "$DATA/samba"

# Portal 系統檔
mkdir -p "$PORTAL"/{app,logs,scripts,backups,ftps_pasv,venv}

# Log 目錄
mkdir -p /var/log/sf-portal

echo "[ok] 目錄結構建立完成"
ls -la "$DATA"
echo ""
ls -la "$PORTAL"
