#!/bin/bash
# 建立 SFTP 業務代號帳號 (對齊主管圖 u0X 模型)
# v2.0.0.1 大改:
#   - 改成單一帳號邏輯 (預設 u01t), 對齊使用者「先一個帳號 PoC」
#   - shell 預設 /sbin/nologin (純 SFTP, 不互動)
#   - 不 prompt 密碼 — 用 SF_PASSWORD 環境變數帶
#   - 多帳號用 SF_ACCOUNTS="u01 u02 u03"
set -euo pipefail

DATA="${SF_DATA_ROOT:-/data/exchange}"
ACCOUNTS=(${SF_ACCOUNTS:-u01t})
PASSWORD="${SF_PASSWORD:-}"   # 不寫死, 跑時帶
SHELL_BIN="/sbin/nologin"     # SFTP only, 不允許 shell

echo "=== 建立 SFTP 帳號 (對齊 u0X 業務代號) ==="
echo "帳號:     ${ACCOUNTS[*]}"
echo "Shell:    $SHELL_BIN (純 SFTP)"
echo "密碼:     $([ -n "$PASSWORD" ] && echo '已提供' || echo '未提供 (帳號建好但無法登入)')"
echo ""

# 確保 sftp_users 群組存在
getent group sftp_users >/dev/null || groupadd sftp_users

# 逐帳號建立
for a in "${ACCOUNTS[@]}"; do
    home="$DATA/$a"

    # 1. 建帳號 (不互動)
    if id "$a" &>/dev/null; then
        echo "[skip] 帳號 $a 已存在"
    else
        useradd -g sftp_users \
                -d "$home" \
                -s "$SHELL_BIN" \
                -M \
                -c "SF SFTP business account" \
                "$a"
        echo "[ok] 建立帳號 $a (home=$home, shell=$SHELL_BIN)"
    fi

    # 2. 設密碼 (如果有提供)
    if [[ -n "$PASSWORD" ]]; then
        echo "$a:$PASSWORD" | chpasswd
        echo "[ok] $a 密碼已設"
    else
        echo "[warn] $a 未設密碼 (帶 SF_PASSWORD=xxx 再跑或手動 passwd $a)"
    fi
done

echo ""
echo "=== 驗證 ==="
getent passwd | grep -E "^($(IFS='|'; echo "${ACCOUNTS[*]}"))" || echo "(無)"

echo ""
echo "下一步: 從別台主機測 SFTP:"
echo "  sftp $ACCOUNTS@$(hostname -I | awk '{print $1}')"
