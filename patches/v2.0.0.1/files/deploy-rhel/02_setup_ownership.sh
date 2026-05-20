#!/bin/bash
# 設定目錄擁有權 (對應 Windows NTFS ACL)
# v2.0.0.1: 改用 u0X 業務代號模型, 不再 sftp_<dept> 命名
set -euo pipefail

DATA="${SF_DATA_ROOT:-/data/exchange}"
PORTAL="${SF_PORTAL_ROOT:-/opt/portal}"
ACCOUNTS=(${SF_ACCOUNTS:-u01t})

echo "=== 設定目錄權限 ==="

# 建立 sftp 群組
getent group sftp_users >/dev/null || groupadd sftp_users
echo "[ok] 群組 sftp_users"

# 建立 portal 服務帳號 (跑 Flask 用)
if ! id -u portal &>/dev/null; then
    useradd -r -m -d "$PORTAL" -s /bin/bash portal
    echo "[ok] 服務帳號 portal"
fi

# DataRoot 根: root 擁有
chown root:root "$DATA"
chmod 755 "$DATA"

# === 重要: chroot 父目錄必須 root 擁有 + 700/755 ===
# OpenSSH ChrootDirectory 要求: 該目錄與所有上層必須 root:root + 不可 group-writable
# 所以 /data/exchange/u01t/ 是 root:root 0755, 子目錄 inbound/ 才給 sftp 帳號寫
for a in "${ACCOUNTS[@]}"; do
    # chroot 點本身 (帳號根)
    chown root:root "$DATA/$a"
    chmod 0755 "$DATA/$a"

    # 子目錄: 該帳號 + portal 可讀寫
    for sub in inbound pending outbound archive error; do
        if [[ -d "$DATA/$a/$sub" ]]; then
            chown "$a":sftp_users "$DATA/$a/$sub" 2>/dev/null || \
                chown root:sftp_users "$DATA/$a/$sub"
            chmod 2770 "$DATA/$a/$sub"
            # 給 portal 帳號讀寫權 (簽核搬檔用)
            setfacl -m u:portal:rwx "$DATA/$a/$sub" 2>/dev/null || true
            setfacl -d -m u:portal:rwx "$DATA/$a/$sub" 2>/dev/null || true
        fi
    done
    echo "[ok] $DATA/$a (chroot root:root 0755, sub root:sftp_users 2770)"
done

# Portal 系統目錄: portal 帳號擁有
chown -R portal:portal "$PORTAL"
chmod -R 750 "$PORTAL"
echo "[ok] $PORTAL (portal:portal)"

# Log 目錄
chown portal:portal /var/log/sf-portal
chmod 750 /var/log/sf-portal

# SELinux context (允許 nginx 反向代理)
if command -v semanage &>/dev/null; then
    semanage fcontext -a -t httpd_sys_content_t "${PORTAL}/app(/.*)?" 2>/dev/null || true
    restorecon -Rv "$PORTAL/app" 2>/dev/null || true
    setsebool -P httpd_can_network_connect 1 2>/dev/null || true
    echo "[ok] SELinux context"
fi

echo ""
echo "權限設定完成"
ls -la "$DATA"
