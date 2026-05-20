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

# === Step 4: 嚴格驗證 (retry 60 秒) ===
step "Step 4: 驗證部署 (等服務真起來)"

# 基本 service 狀態
echo ""
echo "Service 即時狀態:"
for svc in sshd nginx postgresql sf-portal; do
    s=$(systemctl is-active $svc 2>/dev/null || echo not-found)
    printf "  %-15s : %s\n" "$svc" "$s"
done

# 嚴格等 Portal 真的起來 (retry 30 次, 每次 2 秒, 共 60 秒)
echo ""
echo "等 Portal 起來 (retry 60s)..."
PORTAL_OK=false
for i in $(seq 1 30); do
    # sf-portal service active
    if ! systemctl is-active sf-portal &>/dev/null; then
        sleep 2
        continue
    fi
    # 直連 Flask 5000 (Portal /auth/login 通常 200/302)
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 http://localhost:5000/auth/login 2>/dev/null || echo 000)
    if [[ "$code" =~ ^(200|302|401|403)$ ]]; then
        PORTAL_OK=true
        ok "Portal 起來了 (HTTP $code)"
        break
    fi
    sleep 2
done

# 嚴格驗證 nginx 反向代理
NGINX_OK=false
if $PORTAL_OK; then
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 http://localhost/ 2>/dev/null || echo 000)
    if [[ "$code" =~ ^(200|302|401|403)$ ]]; then
        NGINX_OK=true
        ok "nginx 反向代理 OK (HTTP $code)"
    fi
fi

# === 結果分流 ===
if ! $PORTAL_OK; then
    echo ""
    echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║   ❌ 驗證失敗 — Portal 沒起來, 暫停 USER 測試                ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo "=== sf-portal service 狀態 ==="
    systemctl status sf-portal --no-pager -l 2>&1 | head -20

    echo ""
    echo "=== sf-portal log (最後 50 行) ==="
    journalctl -u sf-portal -n 50 --no-pager 2>&1 || echo "(no log)"

    echo ""
    echo "=== 09_deploy_portal.sh 重跑診斷 ==="
    if [[ -f "$SF_TARGET/deploy-rhel/09_deploy_portal.sh" ]]; then
        sudo bash "$SF_TARGET/deploy-rhel/09_deploy_portal.sh" 2>&1 | tail -30
    fi

    echo ""
    echo "→ 修完後跑 health check:"
    echo "  curl -fsSL https://github.com/alienid4/cl_ftp/raw/main/deploy-rhel/health_check.sh | sudo bash"
    echo ""
    echo "→ 或重跑本腳本:"
    echo "  curl -fsSL https://github.com/alienid4/cl_ftp/raw/main/release-zip/latest-install.sh | sudo bash"
    exit 1
fi

# === 成功 ===
step "✅ 完成 - 可給 USER 測試"
MAIN_IP=$(ip -4 addr | grep -E 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}' | cut -d/ -f1)

echo ""
echo -e "${BOLD}${GREEN}訪問網址 (已驗證可達):${NC}"
echo ""
if $NGINX_OK; then
    echo -e "  ${BOLD}Portal (給 USER 用)${NC}  : http://$MAIN_IP/"
    echo -e "  Portal (debug)        : http://$MAIN_IP:5000/"
else
    echo -e "  ${YELLOW}Portal (僅 Flask 直連)${NC} : http://$MAIN_IP:5000/"
    warn "nginx 80 沒回應, 暫時用 5000 port; nginx 之後修"
fi
echo "  SFTP                  : sftp $SF_ACCOUNTS@$MAIN_IP   (密碼: $SF_PASSWORD)"
echo "  SSH 管理              : ssh root@$MAIN_IP"

echo ""
ok "Online Install 完成, 服務驗證通過, 可給 USER 測試 ✓"
echo ""
echo "→ 之後升級:"
echo "    cd $SF_TARGET && sudo git pull && sudo ./deploy-rhel/install_all.sh"
echo "    sudo dnf upgrade"
