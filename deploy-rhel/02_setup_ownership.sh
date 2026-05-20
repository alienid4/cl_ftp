#!/bin/bash
# 設定目錄擁有權 (取代 Windows NTFS ACL)
# 對應 Windows: deploy/02_setup_ntfs_acl.ps1
set -euo pipefail

DATA="${SF_DATA_ROOT:-/data/exchange}"
PORTAL="${SF_PORTAL_ROOT:-/opt/portal}"
DEPTS=(${SF_DEPTS:-HR FIN OPS})

echo "=== 設定目錄權限 ==="

# 建立 sftp 群組
getent group sftp_users >/dev/null || groupadd sftp_users
echo "[ok] 群組 sftp_users"

# 建立 portal 服務帳號 (跑 Flask 用)
if ! id -u portal &>/dev/null; then
    useradd -r -m -d "$PORTAL" -s /bin/bash portal
    echo "[ok] 服務帳號 portal"
fi

# DataRoot 根: root 擁有, 其他人不能進 (避免越權)
chown root:root "$DATA"
chmod 755 "$DATA"

# 各部門目錄: 該部門 sftp 帳號 + portal 可讀寫
for d in "${DEPTS[@]}"; do
    sftp_acct="sftp_$(echo $d | tr A-Z a-z)"   # sftp_hr / sftp_fin / sftp_ops

    # ACL 用 setfacl (取代 NTFS ACL)
    chown root:sftp_users "$DATA/$d"
    chmod 2770 "$DATA/$d"   # setgid: 子檔案繼承群組

    # 給 portal 帳號讀寫權
    setfacl -R -m u:portal:rwx "$DATA/$d" 2>/dev/null || true
    setfacl -d -m u:portal:rwx "$DATA/$d" 2>/dev/null || true

    echo "[ok] $DATA/$d (sftp_users + portal)"
done

# Portal 系統目錄: portal 帳號擁有
chown -R portal:portal "$PORTAL"
chmod -R 750 "$PORTAL"
echo "[ok] $PORTAL (portal:portal)"

# Log 目錄
chown portal:portal /var/log/sf-portal
chmod 750 /var/log/sf-portal

# SELinux context (允許 nginx 反向代理到 portal)
if command -v semanage &>/dev/null; then
    semanage fcontext -a -t httpd_sys_content_t "${PORTAL}/app(/.*)?" 2>/dev/null || true
    restorecon -Rv "$PORTAL/app" 2>/dev/null || true
    # 允許 nginx 對外連 (proxy)
    setsebool -P httpd_can_network_connect 1 2>/dev/null || true
    echo "[ok] SELinux context"
fi

echo ""
echo "權限設定完成"
ls -la "$DATA"
echo ""
ls -la "$PORTAL"
