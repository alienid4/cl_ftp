#!/bin/bash
#
# install_satellite.sh - SF 主機從 Red Hat Satellite 部署 (v2.1.0)
#
# 對應 v2.0.x install_offline.sh, 但完全不用 bundle:
#   - SF 主機註冊到公司 Satellite
#   - dnf install 從 Satellite 抓套件 (自動解 dependency)
#   - 沒有 file conflict (因為 Satellite 跟主機是同版 RHEL)
#
# 用法:
#   1. 跟公司 IT 拿 Satellite URL + Org + Activation Key
#   2. 編輯本檔最上方環境變數
#   3. sudo bash install_satellite.sh
#
#   或:
#   sudo SATELLITE_URL=https://sat.corp \
#        SATELLITE_ORG=MyOrg \
#        SATELLITE_KEY=sf-server-key \
#        SF_ACCOUNTS=u01t SF_PASSWORD='1qaz@WSX' \
#        bash install_satellite.sh
#
set -euo pipefail

# === 必填: Satellite 連線 (跟 IT 拿) ===
SATELLITE_URL="${SATELLITE_URL:-}"          # 例: https://satellite.corp.local
SATELLITE_ORG="${SATELLITE_ORG:-}"          # 例: Default_Organization
SATELLITE_KEY="${SATELLITE_KEY:-}"          # 例: sf-server-key (Activation Key)

# === 業務帳號 (可改) ===
SF_ACCOUNTS="${SF_ACCOUNTS:-u01t}"
SF_PASSWORD="${SF_PASSWORD:-1qaz@WSX}"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
BOLD='\033[1m'
step()  { echo ""; echo -e "${CYAN}=== $* ===${NC}"; }
ok()    { echo -e "${GREEN}[ok]${NC} $*"; }
warn()  { echo -e "${YELLOW}[warn]${NC} $*"; }
fail()  { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }

echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║   SF File Exchange Server — Satellite 部署 v2.1.0            ║${NC}"
echo -e "${BOLD}${CYAN}║   (跳過 bundle, 用公司 Satellite 直接 dnf install)           ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

[[ $EUID -eq 0 ]] || fail "請 sudo: sudo bash $0"

# === Step 0: 前置檢查 ===
step "Step 0: 前置檢查"

# RHEL 版本
if ! grep -qE 'release [89]' /etc/redhat-release 2>/dev/null; then
    fail "不是 RHEL 8/9: $(cat /etc/redhat-release 2>/dev/null)"
fi
ok "OS: $(cat /etc/redhat-release)"

# Satellite 參數
if [[ -z "$SATELLITE_URL" || -z "$SATELLITE_ORG" || -z "$SATELLITE_KEY" ]]; then
    fail "請設環境變數:
  SATELLITE_URL  = $SATELLITE_URL
  SATELLITE_ORG  = $SATELLITE_ORG
  SATELLITE_KEY  = $SATELLITE_KEY

跟你 IT / Satellite admin 拿這 3 個值, 然後:
  sudo SATELLITE_URL=https://sat.corp.local \\
       SATELLITE_ORG=YourOrg \\
       SATELLITE_KEY=sf-server-key \\
       bash $0
"
fi
ok "Satellite: $SATELLITE_URL (org=$SATELLITE_ORG)"

# === Step 1: 註冊 Satellite ===
step "Step 1: 註冊 SF 主機到 Satellite"

# 檢查是不是已註冊
if subscription-manager status 2>/dev/null | grep -q 'Current'; then
    ok "已註冊 Satellite (subscription Current)"
else
    echo "[exec] 抓 katello-ca-consumer rpm..."
    CA_URL="$SATELLITE_URL/pub/katello-ca-consumer-latest.noarch.rpm"
    dnf install -y --nogpgcheck "$CA_URL" 2>&1 | tail -5

    echo "[exec] subscription-manager register..."
    subscription-manager register \
        --org="$SATELLITE_ORG" \
        --activationkey="$SATELLITE_KEY" \
        --force 2>&1 | tail -5

    subscription-manager refresh
    ok "Satellite 註冊完成"
fi

# === Step 2: 確認 repo ===
step "Step 2: 確認 RHEL repo 可達"
dnf repolist 2>&1 | grep -E 'rhel|appstream|baseos' || warn "沒看到預期 repo, 確認 Satellite Content View 設定"
ok "Repo 設定 OK"

# === Step 3: dnf install 所有套件 (從 Satellite, 自動解 dep) ===
step "Step 3: 裝套件 (從 Satellite, 不用 bundle, 不會 file conflict)"

PACKAGES=(
    # 基本
    git curl wget tar unzip vim-enhanced bc openssl rsync

    # OpenSSH (應該預裝)
    openssh openssh-server openssh-clients

    # PostgreSQL
    postgresql postgresql-server postgresql-contrib python3-psycopg2

    # Web (nginx + Python)
    nginx python3 python3-pip python3-virtualenv

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

echo "套件數: ${#PACKAGES[@]}"
dnf install -y "${PACKAGES[@]}" 2>&1 | tail -10
ok "所有套件已安裝 (從 Satellite)"

# === Step 4: clone repo (Satellite 不管 Git, 用 GitHub 或公司內部 Git) ===
step "Step 4: clone SF repo"
mkdir -p /opt/sf

if [[ ! -d /opt/sf/.git ]]; then
    if [[ -n "${SF_GIT_URL:-}" ]]; then
        git clone "$SF_GIT_URL" /opt/sf
    else
        # 預設從 GitHub (如果有外網)
        git clone https://github.com/alienid4/cl_ftp /opt/sf 2>&1 | tail -3
    fi
    ok "Repo cloned: /opt/sf"
else
    cd /opt/sf && git pull 2>&1 | tail -3
    ok "Repo 更新"
fi

# === Step 5: 跑 install_all.sh ===
step "Step 5: 跑 deploy-rhel/install_all.sh"
chmod +x /opt/sf/deploy-rhel/*.sh
cd /opt/sf
SF_ACCOUNTS="$SF_ACCOUNTS" SF_PASSWORD="$SF_PASSWORD" \
    bash ./deploy-rhel/install_all.sh

# === 完成 ===
step "完成 - 訪問網址"
MAIN_IP=$(ip -4 addr | grep -E 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}' | cut -d/ -f1)
if [[ -n "$MAIN_IP" ]]; then
    echo "  Portal HTTP : http://$MAIN_IP/"
    echo "  SFTP        : sftp $SF_ACCOUNTS@$MAIN_IP   (密碼: $SF_PASSWORD)"
fi
echo ""
ok "Satellite 部署 v2.1.0 完成 ✓"
echo ""
echo "→ 完全沒用 bundle / install_offline.sh / EXCLUDE_PATTERN"
echo "→ 完全沒 file conflict"
echo "→ 之後升級: cd /opt/sf && git pull && sudo ./deploy-rhel/install_all.sh"
