#!/bin/bash
#
# SF File Exchange Server - RHEL Offline Installer
# v2.0.0.7: 過濾掉 base packages (主機已有, bundle 不該取代)
#           解 redhat-release / systemd / kernel / glibc 等檔案衝突
#

set -euo pipefail
BUNDLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'
step()  { echo ""; echo -e "${CYAN}=== $* ===${NC}"; }
ok()    { echo -e "${GREEN}[ok]${NC} $*"; }

[[ $EUID -eq 0 ]] || { echo "[FAIL] 請用 sudo"; exit 1; }

step "Step 1: 安裝 RPM (離線, 用 bundle 內的)"
if [[ -d "$BUNDLE_DIR/rpms" ]] && ls "$BUNDLE_DIR/rpms"/*.rpm &>/dev/null; then
    total=$(ls $BUNDLE_DIR/rpms/*.rpm | wc -l)

    # v2.0.0.7: 過濾掉主機已有的 base packages
    # 這些被 dnf download 連帶抓進來, 但主機不該被取代
    EXCLUDE_PATTERN='rocky-release|redhat-release|centos-release|almalinux-release|oraclelinux-release|fedora-release|systemd-|kernel-|glibc-|filesystem-|setup-|bash-|libc-|libgcc-|libstdc'

    # 用 grep -vE 過濾
    SAFE_RPMS=$(ls "$BUNDLE_DIR"/rpms/*.rpm | grep -vE "/($EXCLUDE_PATTERN)" || true)
    safe_count=$(echo "$SAFE_RPMS" | grep -c '\.rpm$' || echo 0)

    echo "RPM 總數: $total"
    echo "過濾掉 base packages: $((total - safe_count)) 個"
    echo "安裝: $safe_count 個 (PostgreSQL / nginx / Samba / Python / etc.)"
    echo ""

    if [[ -z "$SAFE_RPMS" ]]; then
        echo "[FAIL] 過濾後沒 RPM 可裝, 請檢查 bundle"
        exit 1
    fi

    # dnf install (--skip-broken 雙保險)
    dnf install -y --disablerepo='*' --skip-broken $SAFE_RPMS 2>&1 | tail -10
    ok "RPM 安裝完成"
else
    echo "[skip] $BUNDLE_DIR/rpms 沒有 RPM"
fi

step "Step 2: 拷 repo 到 /opt/sf"
mkdir -p /opt/sf
if [[ -d "$BUNDLE_DIR/repo" ]]; then
    cp -r "$BUNDLE_DIR/repo/"* /opt/sf/
    ok "Repo 拷到 /opt/sf"
fi

step "Step 3: 拷 Python wheels"
mkdir -p /opt/sf/python_wheels
if [[ -d "$BUNDLE_DIR/wheels" ]]; then
    cp -r "$BUNDLE_DIR/wheels/"* /opt/sf/python_wheels/
    ok "Wheels 放在 /opt/sf/python_wheels ($(ls /opt/sf/python_wheels | wc -l) 檔)"
fi

step "Step 4: 跑 install_all.sh"
cd /opt/sf
chmod +x deploy-rhel/*.sh
bash ./deploy-rhel/install_all.sh "$@"
