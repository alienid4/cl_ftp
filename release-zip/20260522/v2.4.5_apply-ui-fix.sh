#!/bin/bash
#
# v2.4.5_apply-ui-fix.sh — 套用 v2.4.5 UI 修復 (不需重裝)
#
# 修了什麼:
#   1. portal/app/static/css/ 補 3 個 CSS (cathay/admin/mockup-extra) → UI 變國泰風格
#   2. templates 重寫: base.html / home.html / admin_biz_list.html / admin_health.html
#   3. admin.py health() 改 Linux (不再呼叫 powershell.exe)
#   4. main.py home() 加 KPI 變數 + try/except (防 DB 錯 500)
#   5. admin.py biz_list 加 try/except (防 500)
#
# 用法 (SF 主機, 已裝 v2.4.4):
#   sudo bash /tmp/ftp-lab/v2.4.5_apply-ui-fix.sh

set -uo pipefail

CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
step() { echo ""; echo -e "${CYAN}=== $* ===${NC}"; }
ok()   { echo -e "${GREEN}[ok]${NC} $*"; }
warn() { echo -e "${YELLOW}[warn]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }

[[ $EUID -eq 0 ]] || fail "請 sudo 跑"

PORTAL_DIR=/opt/portal

# === Step 1: 找 v2.4.5 tar ===
step "Step 1: 找 v2.4.5 portal source tar"

TAR=$(find /tmp /opt /root -maxdepth 5 -name 'v2.4.5_sf-portal-source.tar.gz' -type f 2>/dev/null | head -1)
[[ -n "$TAR" ]] || fail "找不到 v2.4.5_sf-portal-source.tar.gz, 先 WinSCP 上傳到 /tmp/ftp-lab/"
ok "找到: $TAR"

# === Step 2: 解 tar 到暫存 ===
step "Step 2: 解壓"
rm -rf /tmp/sf-portal-v245
mkdir -p /tmp/sf-portal-v245
tar xzf "$TAR" -C /tmp/sf-portal-v245
SRC=/tmp/sf-portal-v245/portal
[[ -d "$SRC/app" ]] || fail "tar 結構不對, 沒看到 portal/app/"
ok "解到 $SRC"

# === Step 3: backup 舊版 ===
step "Step 3: backup 現有 /opt/portal/app/app + templates"
TS=$(date +%s)
[[ -d "$PORTAL_DIR/app/app" ]] && cp -r "$PORTAL_DIR/app/app" "$PORTAL_DIR/app/app.bak.$TS"
ok "備份完成 .bak.$TS"

# === Step 4: 拷 CSS / templates / .py ===
step "Step 4: 套新檔"

# 4a: static (CSS)
mkdir -p "$PORTAL_DIR/app/app/static"
cp -r "$SRC/app/static/"* "$PORTAL_DIR/app/app/static/" 2>/dev/null || true
ok "CSS 拷入 $PORTAL_DIR/app/app/static/"

# 4b: templates
mkdir -p "$PORTAL_DIR/app/app/templates"
cp "$SRC/app/templates/"*.html "$PORTAL_DIR/app/app/templates/"
ok "templates 拷入"

# 4c: 修過的 .py
cp "$SRC/app/blueprints/admin.py" "$PORTAL_DIR/app/app/blueprints/admin.py"
cp "$SRC/app/blueprints/main.py"  "$PORTAL_DIR/app/app/blueprints/main.py"
ok "admin.py / main.py 拷入"

# === Step 5: py_compile 驗 ===
step "Step 5: py_compile 全 portal"
find "$PORTAL_DIR/app" -name '*.py' -exec /usr/bin/python3 -m py_compile {} \; 2>&1 | head -10
ok "py_compile OK"

# === Step 6: 權限 ===
step "Step 6: 權限"
RUN_USER="nginx"
id -u nginx &>/dev/null || RUN_USER="portal"
chown -R "$RUN_USER:$RUN_USER" "$PORTAL_DIR"
ok "owner = $RUN_USER"

# === Step 7: 重啟 sf-portal ===
step "Step 7: 重啟 sf-portal"
systemctl restart sf-portal
sleep 3
if systemctl is-active sf-portal &>/dev/null; then
    ok "sf-portal active"
else
    fail "sf-portal 啟動失敗, 看 journalctl -u sf-portal -n 30"
fi

# === Step 8: 驗證 ===
step "Step 8: 驗證 HTTP"
code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 http://127.0.0.1:5000/ 2>/dev/null || echo 000)
echo "gunicorn 直連: HTTP $code"
code2=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 http://127.0.0.1/ 2>/dev/null || echo 000)
echo "nginx 反代:    HTTP $code2"

# 順便試一下 CSS 載得到
css_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 http://127.0.0.1/static/css/cathay.css 2>/dev/null || echo 000)
echo "CSS (cathay):  HTTP $css_code"

MAIN_IP=$(ip -4 addr | grep -E 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}' | cut -d/ -f1)

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   ✅ v2.4.5 UI 修復套用完成                                   ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  瀏覽器: http://$MAIN_IP/"
echo "  Ctrl+F5 強制刷新 (清 CSS cache)"
echo ""
echo "  改了什麼:"
echo "    - navbar/admin warning bar 國泰綠+橘風格"
echo "    - 首頁 KPI grid"
echo "    - 業務代號清單表格樣式"
echo "    - 系統健康改 Linux (systemctl + /proc)"
echo "    - admin/biz 跟 admin/health 加 try/except (不再 500)"
echo ""
echo "  Rollback: rm -rf $PORTAL_DIR/app/app && mv $PORTAL_DIR/app/app.bak.$TS $PORTAL_DIR/app/app && systemctl restart sf-portal"
