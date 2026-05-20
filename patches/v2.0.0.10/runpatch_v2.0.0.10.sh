#!/bin/bash
#
# runpatch_v2.0.0.10.sh - SF File Exchange Server 一鍵 Patch + 部署
# v2.0.0.10: 加 openssl-fips-provider + crypto-policies 進 EXCLUDE
#
set -euo pipefail

RUNPATCH_VERSION="v2.0.0.10"
RUNPATCH_DATE="2026-05-20"
RUNPATCH_FEATURES="+ openssl-fips-provider + crypto-policies filter"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
BOLD='\033[1m'
step()  { echo ""; echo -e "${CYAN}=== $* ===${NC}"; }
ok()    { echo -e "${GREEN}[ok]${NC} $*"; }
warn()  { echo -e "${YELLOW}[warn]${NC} $*"; }
fail()  { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }

SF_ACCOUNTS="${SF_ACCOUNTS:-u01t}"
SF_PASSWORD="${SF_PASSWORD:-1qaz@WSX}"

echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║   SF File Exchange Server — RUNPATCH ${RUNPATCH_VERSION}               ║${NC}"
echo -e "${BOLD}${CYAN}║   Date: ${RUNPATCH_DATE}                                           ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo "  Features: $RUNPATCH_FEATURES"
echo ""

[[ $EUID -eq 0 ]] || fail "請 sudo: sudo bash $0"

# === Step 1: Auto-find sf-bundle ===
step "Step 1: 找 sf-bundle/"
CANDIDATES=(
    "$(pwd)/sf-bundle" "$(pwd)/../sf-bundle"
    "/tmp/ftp-lab/sf-bundle" "/opt/install/sf-bundle"
    "/opt/sf-bundle" "/tmp/sf-bundle"
    "$HOME/sf-bundle" "$HOME/Downloads/sf-bundle" "/root/sf-bundle"
)
SF_BUNDLE=""
for c in "${CANDIDATES[@]}"; do
    if [[ -f "$c/install_offline.sh" ]]; then
        SF_BUNDLE="$(cd "$c" && pwd)"
        ok "找到: $SF_BUNDLE"; break
    fi
done
[[ -n "$SF_BUNDLE" ]] || fail "找不到 sf-bundle/"

# === Step 2: 套 patch ===
step "Step 2: 套 patch $RUNPATCH_VERSION"
cd "$SF_BUNDLE"

# idempotent: 檢查是否含 openssl-fips-provider
if grep -q 'openssl-fips-provider' install_offline.sh; then
    ok "patch v2.0.0.10 已套用過, skip"
else
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    cp install_offline.sh "install_offline.sh.bak.$TIMESTAMP"
    ok "原檔備份: install_offline.sh.bak.$TIMESTAMP"

    # 寫入 v2.0.0.10 版 install_offline.sh
    cat > install_offline.sh <<'INSTALL_EOF'
#!/bin/bash
# install_offline.sh v2.0.0.10 (+ openssl-fips-provider + crypto-policies)
set -euo pipefail
BUNDLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'
step()  { echo ""; echo -e "${CYAN}=== $* ===${NC}"; }
ok()    { echo -e "${GREEN}[ok]${NC} $*"; }

[[ $EUID -eq 0 ]] || { echo "[FAIL] 請用 sudo"; exit 1; }

echo ""
echo "  install_offline.sh v2.0.0.10 (含 openssl-fips-provider filter)"
echo ""

step "Step 1: 安裝 RPM (過濾 base + OS release + crypto)"
if [[ -d "$BUNDLE_DIR/rpms" ]] && ls "$BUNDLE_DIR/rpms"/*.rpm &>/dev/null; then
    total=$(ls $BUNDLE_DIR/rpms/*.rpm | wc -l)
    EXCLUDE_PATTERN='openssl-fips-provider|crypto-policies|rocky-release|redhat-release|centos-release|almalinux-release|oraclelinux-release|fedora-release|systemd-|kernel-|glibc-|filesystem-|setup-|bash-|libc-|libgcc-|libstdc'
    SAFE_RPMS=$(ls "$BUNDLE_DIR"/rpms/*.rpm | grep -vE "/($EXCLUDE_PATTERN)" || true)
    safe_count=$(echo "$SAFE_RPMS" | grep -c '\.rpm$' || echo 0)
    excluded=$((total - safe_count))
    echo "RPM 總數: $total / 過濾掉: $excluded / 安裝: $safe_count"
    [[ -n "$SAFE_RPMS" ]] || { echo "[FAIL] 過濾後沒 RPM"; exit 1; }
    dnf install -y --disablerepo='*' --skip-broken $SAFE_RPMS 2>&1 | tail -15
    ok "RPM 安裝完成"
fi

step "Step 2: 拷 repo 到 /opt/sf"
mkdir -p /opt/sf
[[ -d "$BUNDLE_DIR/repo" ]] && cp -r "$BUNDLE_DIR/repo/"* /opt/sf/ && ok "Repo OK"

step "Step 3: 拷 Python wheels"
mkdir -p /opt/sf/python_wheels
[[ -d "$BUNDLE_DIR/wheels" ]] && cp -r "$BUNDLE_DIR/wheels/"* /opt/sf/python_wheels/ && ok "Wheels OK"

step "Step 4: 跑 install_all.sh"
cd /opt/sf
chmod +x deploy-rhel/*.sh
bash ./deploy-rhel/install_all.sh "$@"
INSTALL_EOF
    chmod +x install_offline.sh
    ok "install_offline.sh 寫入 v2.0.0.10"
    grep -q 'openssl-fips-provider' install_offline.sh && ok "驗證 OK" || fail "patch 沒套上"
fi

# === Step 3: 跑 install_offline.sh ===
step "Step 3: 跑 install_offline.sh (帳號 $SF_ACCOUNTS, 密碼 ****)"
echo "10 秒後開始, Ctrl+C 取消..."
sleep 10

cd "$SF_BUNDLE"
SF_ACCOUNTS="$SF_ACCOUNTS" SF_PASSWORD="$SF_PASSWORD" bash ./install_offline.sh

step "完成 - 訪問網址"
MAIN_IP=$(ip -4 addr | grep -E 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}' | cut -d/ -f1)
if [[ -n "$MAIN_IP" ]]; then
    echo "  Portal HTTP : http://$MAIN_IP/"
    echo "  SFTP        : sftp $SF_ACCOUNTS@$MAIN_IP   (密碼: $SF_PASSWORD)"
fi
echo ""
ok "$RUNPATCH_VERSION 完成 ✓"
