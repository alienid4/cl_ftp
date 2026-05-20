#!/bin/bash
#
# build_epel_pyrpms.sh — 在有 EPEL 的 Rocky/CentOS 主機抓 Python EPEL RPMs
#                        打成 tar, 供無 EPEL 的 SF 主機用
#
# 用途: USER 的 SF 主機禁 EPEL, 但允許從 git 拉預先打好的 RPM tar
#
# 跑這支的環境需求:
#   - Rocky Linux 9 / CentOS Stream 9 / AlmaLinux 9 (RHEL-compatible)
#   - 能 dnf install epel-release
#   - 能連 EPEL mirror
#
# 用法 (本機 / GitHub Actions container):
#   bash deploy-rhel/build_epel_pyrpms.sh /output
#
# 輸出: /output/sf-epel-pyrpms.tar.gz
#

set -euo pipefail

OUTPUT_DIR="${1:-./output}"
WORK_DIR="$(mktemp -d)"
trap "rm -rf $WORK_DIR" EXIT

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
step() { echo ""; echo -e "${CYAN}=== $* ===${NC}"; }
ok()   { echo -e "${GREEN}[ok]${NC} $*"; }
warn() { echo -e "${YELLOW}[warn]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }

mkdir -p "$OUTPUT_DIR"

step "Step 1: 確認環境 + 啟用 EPEL"

if ! grep -qE 'release 9' /etc/redhat-release 2>/dev/null; then
    warn "不是 EL9 環境, 可能不相容: $(cat /etc/redhat-release 2>/dev/null)"
fi

# 啟用 EPEL (Rocky / Alma 都可以)
dnf install -y epel-release dnf-plugins-core 2>&1 | tail -3
ok "EPEL enabled"

# 啟用 CRB (有些 dep 在這)
dnf config-manager --set-enabled crb 2>/dev/null || \
    dnf config-manager --set-enabled powertools 2>/dev/null || \
    warn "CRB/PowerTools 沒能 enable (Rocky vs CentOS 名稱差異)"

# === Step 2: 列要抓的 EPEL Python 套件 ===
step "Step 2: 列要抓的套件 (Portal 需要的 EPEL Python 套件)"

EPEL_PKGS=(
    # Portal 必要
    python3-flask
    python3-werkzeug      # 注意: RHEL 9 AppStream 可能也有, 但這裡一起抓保險
    python3-gunicorn      # WSGI server (純 EPEL, RHEL 沒)

    # Portal 常用 (依程式碼是否 import)
    python3-flask-login
    python3-flask-session
    python3-pyjwt
    python3-ldap          # AD 認證用

    # Flask 依賴 (dnf download --resolve 會自動抓, 列出來保險)
    python3-jinja2
    python3-itsdangerous
    python3-click
    python3-markupsafe
    python3-blinker
)

echo "要抓 ${#EPEL_PKGS[@]} 個 EPEL Python 套件:"
printf '  - %s\n' "${EPEL_PKGS[@]}"

# === Step 3: dnf download (連帶 dep 一起抓) ===
step "Step 3: dnf download --resolve (自動抓 dep)"

cd "$WORK_DIR"
mkdir -p rpms

# --resolve 會把所有依賴鏈一起抓
# --alldeps 會把已經裝在 OS 的也一起抓 (不要, 我們只要 EPEL 沒裝的)
# 默認: 只抓系統還沒裝的 (dep already installed = skip)
# 這裡用 --resolve, 抓「會 install 的」(含依賴)
dnf download \
    --resolve \
    --destdir="$WORK_DIR/rpms" \
    "${EPEL_PKGS[@]}" 2>&1 | tail -20

ok "下載完成"

echo ""
echo "抓到的 RPM:"
ls -lh "$WORK_DIR/rpms/" | tail -30

RPM_COUNT=$(ls "$WORK_DIR/rpms/"*.rpm 2>/dev/null | wc -l)
TOTAL_SIZE=$(du -sh "$WORK_DIR/rpms/" | awk '{print $1}')
ok "共 $RPM_COUNT 個 RPM, 總大小 $TOTAL_SIZE"

if [[ "$RPM_COUNT" -lt 5 ]]; then
    fail "RPM 數量太少 ($RPM_COUNT), 抓失敗"
fi

# === Step 4: 寫 install 說明 + manifest ===
step "Step 4: 寫 manifest 與 install 提示"

cat > "$WORK_DIR/rpms/README.txt" <<EOF
SF Portal 用 EPEL Python RPM bundle
================================

打包時間: $(date '+%Y-%m-%d %H:%M:%S %Z')
打包機: $(cat /etc/redhat-release 2>/dev/null)
RPM 數: $RPM_COUNT
總大小: $TOTAL_SIZE

安裝方法 (在無 EPEL 的 SF 主機):

  cd /tmp/sf-epel-pyrpms/rpms
  sudo dnf install -y --disablerepo='*' ./*.rpm

  (--disablerepo='*' 避免 dnf 想去找線上 repo)

或單獨指定:

  sudo rpm -Uvh --replacefiles ./*.rpm

對應 fix_portal.sh 已自動處理.
EOF

# manifest 給 fix_portal.sh 驗證用
ls "$WORK_DIR/rpms/"*.rpm | xargs -n1 basename | sort > "$WORK_DIR/rpms/MANIFEST.txt"
ok "MANIFEST.txt 寫入 ($(wc -l < "$WORK_DIR/rpms/MANIFEST.txt") 行)"

# === Step 5: 打 tar ===
step "Step 5: 打 tar.gz"

OUTPUT_FILE="$OUTPUT_DIR/sf-epel-pyrpms.tar.gz"
tar czf "$OUTPUT_FILE" -C "$WORK_DIR" rpms

OUTPUT_SIZE=$(du -sh "$OUTPUT_FILE" | awk '{print $1}')
OUTPUT_SHA=$(sha256sum "$OUTPUT_FILE" | awk '{print $1}')

ok "Output: $OUTPUT_FILE ($OUTPUT_SIZE)"
echo "SHA-256: $OUTPUT_SHA"

# 同時寫 .sha256 file
echo "$OUTPUT_SHA  $(basename "$OUTPUT_FILE")" > "$OUTPUT_FILE.sha256"

step "✅ 完成"
echo ""
echo "下一步:"
echo "  1. 把 $OUTPUT_FILE 放到 git release-zip/"
echo "  2. SF 主機跑 fix_portal.sh 會自動從 raw URL 抓"
echo ""
ls -lh "$OUTPUT_FILE" "$OUTPUT_FILE.sha256"
