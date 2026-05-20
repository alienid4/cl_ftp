#!/bin/bash
#
# runpatch.sh — SF v2.0.0.6 一鍵套用 + 安裝 (工讀生友善版)
#
# 用法:
#   1. SF 主機有外網:
#        curl -fsSL https://github.com/alienid4/cl_ftp/raw/main/patches/v2.0.0.6/runpatch.sh | sudo bash
#
#   2. SF 主機無外網:
#        Windows PC 抓 runpatch.sh → USB 拷到 SF 主機
#        sudo bash runpatch.sh
#
# 這支會自動:
#   1. 找你的 sf-bundle/ 目錄
#   2. 套 v2.0.0.6 patch (改 install_offline.sh 加 --skip-broken)
#   3. 跑 install_offline.sh (預設帳號 u01t, 密碼 1qaz@WSX)
#
# 工讀生不用懂 sed / wget / dnf, 一行貼完成。
#

set -euo pipefail

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
step()  { echo ""; echo -e "${CYAN}=== $* ===${NC}"; }
ok()    { echo -e "${GREEN}[ok]${NC} $*"; }
warn()  { echo -e "${YELLOW}[warn]${NC} $*"; }
fail()  { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }

# 帳號密碼 (可用環境變數覆蓋)
SF_ACCOUNTS="${SF_ACCOUNTS:-u01t}"
SF_PASSWORD="${SF_PASSWORD:-1qaz@WSX}"

echo ""
echo "================================================================"
echo "  SF File Exchange Server - v2.0.0.6 一鍵 Patch + 部署"
echo "  (工讀生友善版, 對齊 SKILL 鐵律 3)"
echo "================================================================"

# === 1. 檢查 root ===
[[ $EUID -eq 0 ]] || fail "請用 sudo: sudo bash $0"

# === 2. Auto-find sf-bundle ===
step "Step 1: 找 sf-bundle/ 目錄"

CANDIDATES=(
    "$(pwd)/sf-bundle"
    "$(pwd)/../sf-bundle"
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

if [[ -z "$SF_BUNDLE" ]]; then
    echo ""
    fail "找不到 sf-bundle/ 目錄 (掃過: ${CANDIDATES[*]})

請先解壓 tar.gz:
  cd /opt/install
  sudo tar xzf sf-rhel-bundle-*.tar.gz
  cd sf-bundle/
  sudo bash $0
"
fi

# === 3. 套 patch (idempotent) ===
step "Step 2: 套 patch (install_offline.sh + --skip-broken)"

cd "$SF_BUNDLE"

if grep -q 'skip-broken' install_offline.sh; then
    ok "patch 已套用過 (含 --skip-broken), skip"
else
    # 備份原檔
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    cp install_offline.sh "install_offline.sh.bak.$TIMESTAMP"
    ok "原檔備份: install_offline.sh.bak.$TIMESTAMP"

    # 改檔
    sed -i 's/--disablerepo/--skip-broken --disablerepo/' install_offline.sh
    ok "已加 --skip-broken"

    # 驗證
    if grep -q 'skip-broken' install_offline.sh; then
        ok "驗證 OK: $(grep 'dnf install' install_offline.sh | head -1 | tr -s ' ')"
    else
        fail "sed 沒生效, 請手動改"
    fi
fi

# === 4. 跑 install_offline.sh ===
step "Step 3: 跑 install_offline.sh (帳號 $SF_ACCOUNTS, 密碼 ****)"
echo ""
echo "10 秒後開始跑..."
echo "  (Ctrl+C 取消)"
echo "  若要改帳號/密碼: sudo SF_ACCOUNTS=xxx SF_PASSWORD=xxx bash $0"
sleep 10

cd "$SF_BUNDLE"
sudo SF_ACCOUNTS="$SF_ACCOUNTS" SF_PASSWORD="$SF_PASSWORD" ./install_offline.sh

# === 5. 顯示訪問網址 ===
step "完成 - 訪問網址"
MAIN_IP=$(ip -4 addr | grep -E 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}' | cut -d/ -f1)
if [[ -n "$MAIN_IP" ]]; then
    echo "  Portal HTTP : http://$MAIN_IP/"
    echo "  SFTP        : sftp $SF_ACCOUNTS@$MAIN_IP   (密碼: $SF_PASSWORD)"
    echo "  RDP / SSH   : $MAIN_IP"
fi

echo ""
ok "工讀生任務完成 ✓"
