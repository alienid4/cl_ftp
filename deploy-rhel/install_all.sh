#!/bin/bash
#
# SF File Exchange Server - RHEL 9 一鍵部署
#
# 用法:
#   git clone https://github.com/alienid4/cl_ftp
#   cd cl_ftp
#   sudo ./deploy-rhel/install_all.sh
#
# 或單獨跑某 step:
#   sudo ./deploy-rhel/03_install_openssh.sh
#
# 對應 Windows: install_offline.ps1 (但你不用懂)
#

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 顏色
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

step() {
    echo ""
    echo -e "${CYAN}================================================================${NC}"
    echo -e "${CYAN} $1${NC}"
    echo -e "${CYAN}================================================================${NC}"
}

ok()   { echo -e "${GREEN}[ok]${NC} $*"; }
warn() { echo -e "${YELLOW}[warn]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }

# 0. 必須是 root
[[ $EUID -eq 0 ]] || fail "請用 sudo 跑"

# 1. RHEL 版本確認
if ! grep -qE 'release [89]' /etc/redhat-release 2>/dev/null; then
    warn "不是 RHEL 8/9, 可能不相容"
fi

# 2. 設定可調整參數 (環境變數或 default)
SF_DATA_ROOT="${SF_DATA_ROOT:-/data/exchange}"
SF_PORTAL_ROOT="${SF_PORTAL_ROOT:-/opt/portal}"
SF_AD_DOMAIN="${SF_AD_DOMAIN:-corp.local}"
SF_AD_JOIN_USER="${SF_AD_JOIN_USER:-Administrator}"
SF_SKIP_AD="${SF_SKIP_AD:-1}"   # 預設先跳過 AD, 等 LDAP 資訊齊備再跑
SF_PORTAL_PORT="${SF_PORTAL_PORT:-5000}"
SF_DB_NAME="${SF_DB_NAME:-file_exchange_audit}"
SF_DB_USER="${SF_DB_USER:-portal}"
SF_DB_PASS="${SF_DB_PASS:-changeme_$(openssl rand -hex 8)}"

export SF_DATA_ROOT SF_PORTAL_ROOT SF_AD_DOMAIN SF_AD_JOIN_USER SF_SKIP_AD
export SF_PORTAL_PORT SF_DB_NAME SF_DB_USER SF_DB_PASS

step "SF File Exchange Server — RHEL 9 一鍵部署"
echo "DataRoot:   $SF_DATA_ROOT"
echo "PortalRoot: $SF_PORTAL_ROOT"
echo "AD Domain:  $SF_AD_DOMAIN (Skip=$SF_SKIP_AD)"
echo "Portal:     port $SF_PORTAL_PORT"
echo "DB:         $SF_DB_NAME / $SF_DB_USER"
echo ""
echo "5 秒後開始, Ctrl+C 取消..."
sleep 5

# 3. 依序跑各 step
SCRIPTS=(
    "00_check_prereqs.sh"
    "01_setup_directories.sh"
    "02_setup_ownership.sh"
    "03_install_openssh.sh"
    "04_create_sftp_accounts.sh"
    "05_setup_firewall.sh"
    "06_install_nginx.sh"
    "07_join_ad.sh"
    "08_setup_postgresql.sh"
    "09_deploy_portal.sh"
    "10_setup_chrony.sh"
    "11_setup_samba.sh"
    "12_setup_logging.sh"
    "13_setup_backup.sh"
    "14_setup_monitoring.sh"
)

RESULTS=()
for s in "${SCRIPTS[@]}"; do
    script_path="$SCRIPT_DIR/$s"
    if [[ ! -f "$script_path" ]]; then
        warn "$s 不存在 (skipping)"
        RESULTS+=("$s|skip|file 不存在")
        continue
    fi

    step "→ $s"
    if bash "$script_path"; then
        RESULTS+=("$s|ok|")
    else
        rc=$?
        warn "$s 失敗 (exit=$rc), 繼續跑下一個"
        RESULTS+=("$s|fail|exit=$rc")
    fi
done

# 4. 總結
step "安裝結束 — Summary"
printf "%-30s %-6s %s\n" "Step" "Status" "Detail"
echo "------------------------------------------------------------"
for r in "${RESULTS[@]}"; do
    IFS='|' read -r name status detail <<< "$r"
    color=$NC
    [[ "$status" == "ok"   ]] && color=$GREEN
    [[ "$status" == "warn" ]] && color=$YELLOW
    [[ "$status" == "fail" ]] && color=$RED
    [[ "$status" == "skip" ]] && color=$YELLOW
    printf "%-30s ${color}%-6s${NC} %s\n" "$name" "$status" "$detail"
done

# 5. 服務狀態 + 訪問網址
echo ""
step "服務狀態 (systemctl status)"
systemctl --no-pager status sshd nginx postgresql sf-portal smb 2>/dev/null | grep -E 'Active|●' || true

echo ""
step "Port 監聽 (ss -tlnp)"
ss -tlnp 2>/dev/null | grep -E ':(22|80|443|5000|5432|445|139)\b' || true

echo ""
step "IP 位址 (ip a)"
ip -4 addr | grep -E 'inet ' | grep -v '127.0.0.1' | awk '{print "  " $2}'

echo ""
step "訪問網址"
MAIN_IP=$(ip -4 addr | grep -E 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}' | cut -d/ -f1)
if [[ -n "$MAIN_IP" ]]; then
    echo "  Portal HTTP    : http://$MAIN_IP:$SF_PORTAL_PORT/"
    echo "  Portal HTTPS   : https://$MAIN_IP/  (需 SSL 憑證, 配置後啟用)"
    echo "  SFTP           : sftp <user>@$MAIN_IP  (帳號未建)"
    echo "  SMB            : smb://$MAIN_IP/<share>  (Samba 已配置時)"
    echo "  SSH 管理       : ssh root@$MAIN_IP  (限白名單 IP)"
fi

echo ""
echo -e "${GREEN}部署完成。${NC}"
echo ""
echo "下一步:"
echo "  1. AD 接入:        sudo SF_SKIP_AD=0 ./deploy-rhel/07_join_ad.sh"
echo "  2. 建 SFTP 帳號:   sudo ./deploy-rhel/04_create_sftp_accounts.sh"
echo "  3. health check:   ./deploy-rhel/health_check.sh"
echo "  4. log:            journalctl -u sf-portal -f"
echo ""
