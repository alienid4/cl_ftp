#!/bin/bash
#
# install_online.sh - SF File Exchange Server 一鍵部署 (有 dnf mirror 環境)
#
# 適用情境: SF 主機能 `dnf install` 公司 mirror (Satellite / yum repo / 內網 mirror)
#           不用 bundle 那套, 不會有 file conflict
#
# 用法 (公司 PC 開 SF 主機 PowerShell/SSH, 貼這一行):
#
#   curl -fsSL https://github.com/alienid4/cl_ftp/raw/main/deploy-rhel/install_online.sh | sudo bash
#
# 改帳號/密碼:
#   curl -fsSL https://github.com/alienid4/cl_ftp/raw/main/deploy-rhel/install_online.sh | sudo SF_ACCOUNTS=u02 SF_PASSWORD='NewP@ss' bash
#

set -euo pipefail

VERSION="install_online v1.0 (2026-05-20)"
SF_ACCOUNTS="${SF_ACCOUNTS:-u01t}"
SF_PASSWORD="${SF_PASSWORD:-1qaz@WSX}"
SF_GIT_URL="${SF_GIT_URL:-https://github.com/alienid4/cl_ftp}"
SF_TARGET="${SF_TARGET:-/opt/sf}"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
BOLD='\033[1m'
step()  { echo ""; echo -e "${CYAN}=== $* ===${NC}"; }
ok()    { echo -e "${GREEN}[ok]${NC} $*"; }
warn()  { echo -e "${YELLOW}[warn]${NC} $*"; }
fail()  { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }

echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║   SF File Exchange Server — Online Install                  ║${NC}"
echo -e "${BOLD}${CYAN}║   $VERSION                              ║${NC}"
echo -e "${BOLD}${CYAN}║   (適合 SF 主機能 dnf install 公司 mirror 的環境)            ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

[[ $EUID -eq 0 ]] || fail "請 sudo: curl ... | sudo bash"

# === Step 0: 前置 ===
step "Step 0: 前置檢查"

if ! grep -qE 'release [89]' /etc/redhat-release 2>/dev/null; then
    warn "不是 RHEL 8/9, 可能不相容: $(cat /etc/redhat-release 2>/dev/null)"
else
    ok "OS: $(cat /etc/redhat-release)"
fi

# 確認 dnf 能 install (試一個輕量套件)
echo "[exec] 確認 dnf 可從 mirror 抓..."
if dnf info bash &>/dev/null; then
    ok "dnf 可用 (mirror 通)"
else
    fail "dnf 連不到 mirror, 確認 /etc/yum.repos.d/ 設定 或 subscription-manager status"
fi

# === Step 1: dnf install 所有需要的套件 ===
step "Step 1: 從 mirror 抓所有套件 (含 dependency)"

# 套件清單
PKG_LIST=(
    # 基本工具
    git curl wget tar unzip vim-enhanced bc openssl rsync

    # OpenSSH (RHEL 預裝)
    openssh openssh-server openssh-clients

    # PostgreSQL
    postgresql postgresql-server postgresql-contrib python3-psycopg2

    # Web stack
    nginx
    python3 python3-pip python3-virtualenv python3-flask

    # Samba
    samba samba-common samba-client cifs-utils

    # NTP
    chrony

    # 監控
    sysstat audit

    # AD 整合
    realmd sssd sssd-tools adcli samba-common-tools krb5-workstation
    oddjob oddjob-mkhomedir authselect

    # 防火牆
    firewalld
)

echo "套件數: ${#PKG_LIST[@]}"
dnf install -y "${PKG_LIST[@]}" 2>&1 | tail -15
ok "所有套件已安裝 (從 mirror)"

# === Step 2: clone SF repo 到 /opt/sf ===
step "Step 2: clone SF repo"

if [[ -d "$SF_TARGET/.git" ]]; then
    cd "$SF_TARGET"
    echo "[exec] git pull..."
    git pull 2>&1 | tail -3 || warn "git pull 失敗 (可能是內網沒外網)"
    ok "Repo 更新: $SF_TARGET"
elif [[ ! -d "$SF_TARGET" ]] || [[ -z "$(ls -A "$SF_TARGET" 2>/dev/null)" ]]; then
    echo "[exec] git clone $SF_GIT_URL $SF_TARGET..."
    git clone "$SF_GIT_URL" "$SF_TARGET" 2>&1 | tail -3
    ok "Repo cloned: $SF_TARGET"
else
    warn "$SF_TARGET 存在但不是 git repo, 跳過 clone"
fi

# === Step 3: 跑 install_all.sh ===
step "Step 3: 部署 SF (deploy-rhel/install_all.sh)"

if [[ ! -d "$SF_TARGET/deploy-rhel" ]]; then
    fail "$SF_TARGET/deploy-rhel 不存在"
fi

cd "$SF_TARGET"
chmod +x deploy-rhel/*.sh

echo "[info] 跑 install_all.sh (約 5-10 分鐘)"
SF_ACCOUNTS="$SF_ACCOUNTS" SF_PASSWORD="$SF_PASSWORD" \
    bash ./deploy-rhel/install_all.sh

# === Step 4: 驗證 + 顯示訪問網址 ===
step "Step 4: 驗證部署"

echo ""
echo "Service 狀態:"
systemctl is-active sshd nginx postgresql sf-portal 2>&1 | paste -sd ', '

echo ""
echo "Port 監聽:"
ss -tlnp 2>/dev/null | grep -E ':(22|80|443|5000|5432)\b' | awk '{print $4}' | sort -u | sed 's/^/  /'

echo ""
echo "Portal HTTP 測試 (本機):"
if curl -s -o /dev/null -w "  http://localhost:5000/  HTTP %{http_code}\n" -m 5 http://localhost:5000/; then
    :
else
    warn "Portal 5000 沒回應"
fi
if curl -s -o /dev/null -w "  http://localhost/      HTTP %{http_code}\n" -m 5 http://localhost/; then
    :
else
    warn "nginx 80 沒回應"
fi

# === 完成 ===
step "完成 - 訪問網址"
MAIN_IP=$(ip -4 addr | grep -E 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}' | cut -d/ -f1)
if [[ -n "$MAIN_IP" ]]; then
    echo "  Portal HTTP   : http://$MAIN_IP/"
    echo "  Portal (Flask): http://$MAIN_IP:5000/"
    echo "  SFTP          : sftp $SF_ACCOUNTS@$MAIN_IP   (密碼: $SF_PASSWORD)"
    echo "  SSH 管理      : ssh root@$MAIN_IP"
fi

echo ""
ok "Online Install 完成 ✓"
echo ""
echo "→ 沒用 bundle / install_offline.sh / EXCLUDE_PATTERN"
echo "→ 沒 file conflict"
echo "→ 之後升級:"
echo "    cd $SF_TARGET && sudo git pull && sudo ./deploy-rhel/install_all.sh"
echo "    sudo dnf upgrade"
echo ""
echo "故障排除 (如果 Portal 沒起來):"
echo "  systemctl status sf-portal --no-pager -l"
echo "  journalctl -u sf-portal -n 100 --no-pager"
echo "  curl -v http://localhost:5000/"
