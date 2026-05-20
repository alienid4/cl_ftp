#!/bin/bash
#
# SF File Exchange Server - RHEL Offline Installer
# v2.0.0.6: 加 --skip-broken 跳過 systemd 等 base packages 衝突
#
# 給 v2.0.0.5 已下載 bundle 的使用者覆蓋用:
#   cd sf-bundle/
#   wget -O install_offline.sh https://github.com/alienid4/cl_ftp/raw/main/release-zip/v2.0.0.6-install_offline.sh
#   chmod +x install_offline.sh
#   sudo SF_ACCOUNTS=u01t SF_PASSWORD='1qaz@WSX' ./install_offline.sh
#

set -euo pipefail
BUNDLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'
step()  { echo ""; echo -e "${CYAN}=== $* ===${NC}"; }
ok()    { echo -e "${GREEN}[ok]${NC} $*"; }

[[ $EUID -eq 0 ]] || { echo "[FAIL] 請用 sudo"; exit 1; }

step "Step 1: 安裝 RPM (離線, 用 bundle 內的)"
if [[ -d "$BUNDLE_DIR/rpms" ]] && ls "$BUNDLE_DIR/rpms"/*.rpm &>/dev/null; then
    echo "RPM 數量: $(ls $BUNDLE_DIR/rpms/*.rpm | wc -l)"
    # v2.0.0.6: --skip-broken 跳過 systemd 等 base packages 衝突
    # 主機本來就裝的 base RPM 不該被 bundle 取代
    dnf install -y --disablerepo='*' --skip-broken "$BUNDLE_DIR"/rpms/*.rpm 2>&1 | tail -10
    ok "RPM 安裝完成 (跳過衝突的 base packages)"
else
    echo "[skip] $BUNDLE_DIR/rpms 沒有 RPM, 跳過"
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
