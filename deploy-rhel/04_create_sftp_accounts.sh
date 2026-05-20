#!/bin/bash
# 建立部門 SFTP 共用帳號 sftp_<dept>
# 對應 Windows: deploy/04_create_sftp_accounts.ps1
set -euo pipefail

DATA="${SF_DATA_ROOT:-/data/exchange}"
DEPTS=(${SF_DEPTS:-HR FIN OPS})
BATCH_MODE="${SF_BATCH_MODE:-1}"   # 預設 batch, 不互動

echo "=== 建立 SFTP 部門共用帳號 ==="

# 確保群組存在 (02 已建)
getent group sftp_users >/dev/null || groupadd sftp_users

# Batch mode: 跳過互動式建帳號
if [[ "$BATCH_MODE" == "1" ]]; then
    echo "[skip] BATCH_MODE=1, 跳過建立 SFTP 帳號"
    echo ""
    echo "之後 PAM 接管 / AP 系統要接時, 手動跑:"
    echo "  sudo SF_BATCH_MODE=0 ./04_create_sftp_accounts.sh"
    echo "或非互動式 (給 PAM 用):"
    echo "  for d in HR FIN OPS; do"
    echo "    useradd -g sftp_users -d $DATA/\$d/inbound -s /sbin/nologin sftp_\${d,,}"
    echo "    echo 'sftp_'\${d,,}':<password>' | chpasswd"
    echo "  done"
    exit 0
fi

# 逐部門建帳號 (互動模式)
for d in "${DEPTS[@]}"; do
    acct="sftp_$(echo $d | tr A-Z a-z)"
    home="$DATA/$d/inbound"

    if id "$acct" &>/dev/null; then
        echo "[skip] $acct 已存在"
    else
        useradd -g sftp_users -d "$home" -s /sbin/nologin -M "$acct"
        echo "[ok] 建立 $acct (home=$home, shell=/sbin/nologin)"
    fi

    # 設密碼 (互動)
    echo ""
    echo "請設定 $acct 密碼 (14 碼以上, 含大小寫+數字+符號):"
    if passwd "$acct"; then
        echo "[ok] $acct 密碼設定"
    else
        echo "[warn] $acct 密碼設定失敗, 帳號保留, 之後再設"
    fi
done

echo ""
echo "SFTP 帳號建立完成"
echo "驗證: getent passwd | grep sftp_"
getent passwd | grep sftp_ || true
