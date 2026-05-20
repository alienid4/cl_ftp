#!/bin/bash
# 設定 OpenSSH (RHEL 原生, 不用裝)
# 對應 Windows: deploy/03_install_openssh.ps1
set -euo pipefail

DATA="${SF_DATA_ROOT:-/data/exchange}"
DEPTS=(${SF_DEPTS:-HR FIN OPS})

echo "=== 設定 OpenSSH (sshd) ==="

# 1. 確保 openssh-server 已裝 (RHEL 預設有)
if ! rpm -q openssh-server &>/dev/null; then
    dnf install -y openssh-server
fi
echo "[ok] openssh-server installed"

# 2. 套用 sshd_config (從 config/ 拷)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$REPO_ROOT/config/sshd_config_linux"

if [[ -f "$TEMPLATE" ]]; then
    # 備份原檔
    if [[ -f /etc/ssh/sshd_config ]] && [[ ! -f /etc/ssh/sshd_config.orig ]]; then
        cp /etc/ssh/sshd_config /etc/ssh/sshd_config.orig
    fi
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%Y%m%d_%H%M%S) 2>/dev/null || true
    cp "$TEMPLATE" /etc/ssh/sshd_config
    chmod 600 /etc/ssh/sshd_config
    echo "[ok] sshd_config 套用 (備份原檔)"
else
    echo "[warn] $TEMPLATE 不存在, 用 RHEL 預設 sshd_config + 簡單客製"
    # 簡單客製: 加 Match Group
    if ! grep -q '^Match Group sftp_users' /etc/ssh/sshd_config; then
        cat >> /etc/ssh/sshd_config <<EOF

# SF File Exchange: chroot sftp_users group to their inbound dir
Match Group sftp_users
    ChrootDirectory $DATA/%u/inbound
    ForceCommand internal-sftp -d /
    AllowTcpForwarding no
    X11Forwarding no
    PermitTunnel no
EOF
    fi
fi

# 3. 驗證設定檔語法
if sshd -t -f /etc/ssh/sshd_config 2>&1 | tee /tmp/sshd_test.log; then
    echo "[ok] sshd_config 語法 OK"
else
    echo "[FAIL] sshd_config 語法錯誤, 還原備份"
    cp /etc/ssh/sshd_config.orig /etc/ssh/sshd_config 2>/dev/null || true
    exit 1
fi

# 4. 啟動 sshd
systemctl enable --now sshd
echo "[ok] sshd $(systemctl is-active sshd)"

# 5. 防火牆放行 22 (firewalld)
if systemctl is-active firewalld &>/dev/null; then
    firewall-cmd --permanent --add-service=ssh
    firewall-cmd --reload
    echo "[ok] firewalld 放行 ssh (port 22)"
fi

# 6. SELinux: 允許 sshd chroot 到非標準路徑
if command -v setsebool &>/dev/null; then
    setsebool -P ssh_chroot_full_access on 2>/dev/null || true
fi

echo ""
echo "OpenSSH 設定完成"
systemctl status sshd --no-pager -l | head -10
