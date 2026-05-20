#!/bin/bash
#
# runpatch.sh v2.0.0.8 - 工讀生一行套用 + 部署
#
# 用法:
#   curl -fsSL https://github.com/alienid4/cl_ftp/raw/main/patches/v2.0.0.8/runpatch.sh | sudo bash
#   sudo bash runpatch.sh
#
# v2.0.0.8 修了什麼:
#   bundle 是 Rocky Linux 9.7 打的, 內含 rocky-release-9.7
#   SF 主機是 RHEL 9.6, 已裝 redhat-release-9.6
#   兩個有同檔 (/etc/system-release, /etc/os-release 等)
#   → 加 rocky-release / centos-release / almalinux-release 進 EXCLUDE
#
set -euo pipefail

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
step()  { echo ""; echo -e "${CYAN}=== $* ===${NC}"; }
ok()    { echo -e "${GREEN}[ok]${NC} $*"; }
warn()  { echo -e "${YELLOW}[warn]${NC} $*"; }
fail()  { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }

SF_ACCOUNTS="${SF_ACCOUNTS:-u01t}"
SF_PASSWORD="${SF_PASSWORD:-1qaz@WSX}"

echo ""
echo "================================================================"
echo "  SF File Exchange Server - v2.0.0.8 一鍵 Patch + 部署"
echo "  (修 rocky-release vs redhat-release file conflict)"
echo "================================================================"

[[ $EUID -eq 0 ]] || fail "請 sudo: sudo bash $0"

# === 1. Auto-find sf-bundle ===
step "Step 1: 找 sf-bundle/"
CANDIDATES=(
    "$(pwd)/sf-bundle"
    "$(pwd)/../sf-bundle"
    "/tmp/ftp-lab/sf-bundle"
    "/opt/install/sf-bundle"
    "/opt/sf-bundle"
    "/tmp/sf-bundle"
    "$HOME/sf-bundle"
    "$HOME/Downloads/sf-bundle"
    "/root/sf-bundle"
)

SF_BUNDLE=""
for c in "${CANDIDATES[@]}"; do
    if [[ -f "$c/install_offline.sh" ]]; then
        SF_BUNDLE="$(cd "$c" && pwd)"
        ok "找到: $SF_BUNDLE"
        break
    fi
done

[[ -n "$SF_BUNDLE" ]] || fail "找不到 sf-bundle/. 先解壓 tar.gz 再跑."

# === 2. 套 patch (idempotent) ===
step "Step 2: 套 patch v2.0.0.8 (擴展 EXCLUDE 包括 rocky-release)"

cd "$SF_BUNDLE"

# 檢查是不是已 v2.0.0.8 版 (含 rocky-release in EXCLUDE)
if grep -q 'rocky-release|redhat-release' install_offline.sh; then
    ok "patch v2.0.0.8 已套用過, skip"
else
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    cp install_offline.sh "install_offline.sh.bak.$TIMESTAMP"
    ok "原檔備份: install_offline.sh.bak.$TIMESTAMP"

    # 抓 v2.0.0.8 (有外網 curl, 無外網 inline)
    if curl -fsS --max-time 5 -o /dev/null https://github.com 2>/dev/null; then
        echo "[info] 從 GitHub 抓 v2.0.0.8 install_offline.sh"
        curl -fsSL https://github.com/alienid4/cl_ftp/raw/main/patches/v2.0.0.8/files/install_offline.sh \
            -o install_offline.sh
        chmod +x install_offline.sh
        ok "已從 GitHub 更新"
    else
        echo "[info] 無外網, inline 寫入"
        cat > install_offline.sh <<'INSTALL_EOF'
#!/bin/bash
# v2.0.0.8 inline 寫入
set -euo pipefail
BUNDLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'
step()  { echo ""; echo -e "${CYAN}=== $* ===${NC}"; }
ok()    { echo -e "${GREEN}[ok]${NC} $*"; }

[[ $EUID -eq 0 ]] || { echo "[FAIL] 請用 sudo"; exit 1; }

step "Step 1: 安裝 RPM (過濾 base packages + OS release)"
if [[ -d "$BUNDLE_DIR/rpms" ]] && ls "$BUNDLE_DIR/rpms"/*.rpm &>/dev/null; then
    total=$(ls $BUNDLE_DIR/rpms/*.rpm | wc -l)
    EXCLUDE_PATTERN='rocky-release|redhat-release|centos-release|almalinux-release|oraclelinux-release|fedora-release|systemd-|kernel-|glibc-|filesystem-|setup-|bash-|libc-|libgcc-|libstdc'
    SAFE_RPMS=$(ls "$BUNDLE_DIR"/rpms/*.rpm | grep -vE "/($EXCLUDE_PATTERN)" || true)
    safe_count=$(echo "$SAFE_RPMS" | grep -c '\.rpm$' || echo 0)
    echo "RPM 總數: $total, 過濾掉: $((total - safe_count)), 安裝: $safe_count"
    [[ -n "$SAFE_RPMS" ]] || { echo "[FAIL] 過濾後沒 RPM"; exit 1; }
    dnf install -y --disablerepo='*' --skip-broken $SAFE_RPMS 2>&1 | tail -10
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
        ok "inline 寫入完成"
    fi

    grep -q 'rocky-release|redhat-release' install_offline.sh && ok "驗證 OK (含 rocky-release filter)" || fail "patch 沒套上"
fi

# === 3. 跑 install_offline.sh ===
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
ok "完成 ✓"
