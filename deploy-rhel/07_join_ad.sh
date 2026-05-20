#!/bin/bash
# 加入 AD domain (realm + sssd + Kerberos)
# 對應 Windows: 加入 AD 網域 (GUI)
set -euo pipefail

AD_DOMAIN="${SF_AD_DOMAIN:-corp.local}"
AD_JOIN_USER="${SF_AD_JOIN_USER:-Administrator}"
SKIP="${SF_SKIP_AD:-1}"

if [[ "$SKIP" == "1" ]]; then
    echo "[skip] SF_SKIP_AD=1, 跳過 AD 整合"
    echo ""
    echo "之後接 AD 時, 跑:"
    echo "  sudo SF_SKIP_AD=0 SF_AD_DOMAIN=corp.local ./07_join_ad.sh"
    exit 0
fi

echo "=== 加入 AD domain: $AD_DOMAIN ==="

# 1. 確認 DNS 指向公司 DC
if ! host -t SRV _kerberos._tcp.$AD_DOMAIN &>/dev/null; then
    echo "[FAIL] DNS 找不到 _kerberos._tcp.$AD_DOMAIN"
    echo "請先設 /etc/resolv.conf 指向公司 DNS Server, 或:"
    echo "  nmcli connection modify <eth0> ipv4.dns 10.x.x.x"
    exit 1
fi

# 2. 裝相關套件
dnf install -y realmd sssd sssd-tools oddjob oddjob-mkhomedir \
               adcli samba-common-tools krb5-workstation \
               authselect 2>&1 | tail -5
echo "[ok] AD 整合套件安裝"

# 3. 探測 domain
realm discover $AD_DOMAIN
echo "[ok] realm discover 成功"

# 4. 加入 domain
echo ""
echo "請輸入 AD 帳號 $AD_JOIN_USER 的密碼:"
realm join --user=$AD_JOIN_USER $AD_DOMAIN
echo "[ok] 已加入 $AD_DOMAIN"

# 5. 套用 SSSD 設定
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "$REPO_ROOT/config/sssd/sssd.conf" ]]; then
    # 備份原檔
    cp /etc/sssd/sssd.conf /etc/sssd/sssd.conf.bak.$(date +%Y%m%d_%H%M%S)
    cp "$REPO_ROOT/config/sssd/sssd.conf" /etc/sssd/sssd.conf
    chmod 600 /etc/sssd/sssd.conf
    chown root:root /etc/sssd/sssd.conf
    systemctl restart sssd
    echo "[ok] sssd.conf 套用"
fi

# 6. 限制誰能登入 (預設只允許 sftp_users + dept_it_admins)
# 這個用 simple_allow_groups 在 sssd.conf 內配
realm permit -g "sftp_users" -g "dept_it_admins" 2>/dev/null || true

# 7. 驗證
echo ""
echo "=== 驗證 ==="
realm list
echo ""
echo "嘗試查 AD 帳號 (測試):"
id Administrator 2>/dev/null || echo "[warn] id 查不到, 可能要等 sssd cache"

echo ""
echo "AD 整合完成。測試: ssh <ad-account>@$(hostname)"
