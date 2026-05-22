#!/bin/bash
#
# v2.4.6_fix-all-functions.sh — SF Portal 功能修復一鍵到位
#
# 對應 USER 抱怨「功能全部失效」(點跑 500 + 空資料 + UI 不對齊):
#
#   1. 套 v2.4.6 source (含 v2.4.5 UI + 新 try/except 防 500)
#   2. apply seed data (3 batch + 9 batchfile + 10 audit log)
#   3. errorhandler(500) 改 inline HTML, 不再 template loop 500
#   4. approval / audit blueprint 加 try/except wrap
#   5. 跑診斷, 報告 8 個 route HTTP 狀態
#
# 用法 (SF 主機):
#   sudo bash /tmp/ftp-lab/v2.4.6_fix-all-functions.sh

set -uo pipefail

CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
BOLD='\033[1m'
step() { echo ""; echo -e "${CYAN}=== $* ===${NC}"; }
ok()   { echo -e "${GREEN}[ok]${NC} $*"; }
warn() { echo -e "${YELLOW}[warn]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }
info() { echo -e "${CYAN}[info]${NC} $*"; }

[[ $EUID -eq 0 ]] || fail "請 sudo 跑"

PORTAL_DIR=/opt/portal
DB_NAME=file_exchange_audit
DB_USER=portal

echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║   v2.4.6 — 修「功能全部失效」 (UI + 500 + seed)              ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"

# === Step 1: 找 v2.4.6 tar ===
step "Step 1: 找 v2.4.6 portal source tar"
TAR=$(find /tmp /opt /root -maxdepth 5 -name 'v2.4.6_sf-portal-source.tar.gz' -type f 2>/dev/null | head -1)
[[ -n "$TAR" ]] || fail "找不到 v2.4.6_sf-portal-source.tar.gz, 先 WinSCP 上傳到 /tmp/ftp-lab/"
ok "找到: $TAR"

# === Step 2: 解壓 ===
step "Step 2: 解 tar"
rm -rf /tmp/sf-portal-v246
mkdir -p /tmp/sf-portal-v246
tar xzf "$TAR" -C /tmp/sf-portal-v246
SRC=/tmp/sf-portal-v246/portal
[[ -d "$SRC/app" ]] || fail "tar 結構不對"
ok "解到 $SRC"

# === Step 3: backup ===
step "Step 3: backup 現有 portal/app"
TS=$(date +%s)
if [[ -d "$PORTAL_DIR/app/app" ]]; then
    cp -r "$PORTAL_DIR/app/app" "$PORTAL_DIR/app/app.bak.$TS"
    ok "備份 .bak.$TS"
fi

# === Step 4: 套新檔 ===
step "Step 4: 套新檔 (templates + CSS + .py)"
mkdir -p "$PORTAL_DIR/app/app/static" "$PORTAL_DIR/app/app/templates" "$PORTAL_DIR/app/app/blueprints"
cp -r "$SRC/app/static/"* "$PORTAL_DIR/app/app/static/" 2>/dev/null || true
cp "$SRC/app/templates/"*.html "$PORTAL_DIR/app/app/templates/"
cp "$SRC/app/__init__.py" "$PORTAL_DIR/app/app/__init__.py"
cp "$SRC/app/blueprints/"*.py "$PORTAL_DIR/app/app/blueprints/"
cp "$SRC/app/"*.py "$PORTAL_DIR/app/app/" 2>/dev/null || true
ok "新檔拷入"

# === Step 5: py_compile ===
step "Step 5: py_compile 驗"
COMPILE_FAIL=$(find "$PORTAL_DIR/app" -name '*.py' -exec /usr/bin/python3 -m py_compile {} \; 2>&1 | head -10)
if [[ -z "$COMPILE_FAIL" ]]; then
    ok "py_compile OK"
else
    warn "$COMPILE_FAIL"
fi

# === Step 6: 權限 ===
step "Step 6: chown"
RUN_USER="nginx"
id -u nginx &>/dev/null || RUN_USER="portal"
chown -R "$RUN_USER:$RUN_USER" "$PORTAL_DIR"
ok "owner = $RUN_USER"

# === Step 7: apply seed data ===
step "Step 7: 套 seed data (3 batch + 9 batchfile + 10 audit log)"
SEED_SQL=$(find "$SRC" /tmp /opt -maxdepth 6 -name '02_seed_data_postgres.sql' -type f 2>/dev/null | head -1)
if [[ -n "$SEED_SQL" ]]; then
    info "seed: $SEED_SQL"
    # cp 到 postgres 可讀位置 (v2.4.3 教訓)
    PG_HOME=$(getent passwd postgres | cut -d: -f6)
    [[ -n "$PG_HOME" ]] || PG_HOME=/var/lib/pgsql
    SEED_TMP="$PG_HOME/sf-seed-$$.sql"
    cp "$SEED_SQL" "$SEED_TMP"
    chown postgres:postgres "$SEED_TMP"
    chmod 644 "$SEED_TMP"
    sudo -u postgres psql -d "$DB_NAME" -f "$SEED_TMP" 2>&1 | tail -10
    rm -f "$SEED_TMP"
    ok "seed data 套入"
else
    warn "找不到 02_seed_data_postgres.sql, 跳過 seed"
fi

# === Step 8: restart ===
step "Step 8: restart sf-portal"
systemctl restart sf-portal
sleep 3
if systemctl is-active sf-portal &>/dev/null; then
    ok "sf-portal active"
else
    fail "sf-portal 啟動失敗, journalctl -u sf-portal -n 30"
fi

# === Step 9: 跑診斷 — 掃所有 route ===
step "Step 9: 掃所有 route HTTP 狀態"

# 模擬登入 (dev_mode 接受任何帳密)
COOKIE=/tmp/sf-portal-cookie-$$.txt
curl -s -c "$COOKIE" -b "$COOKIE" -X POST -d 'username=admin&password=x' http://127.0.0.1:5000/auth/login -o /dev/null

declare -A ROUTES=(
    ["/"]="首頁"
    ["/auth/login"]="登入頁"
    ["/approval/list"]="我的待簽"
    ["/admin/biz"]="業務代號清單"
    ["/admin/biz/new"]="新增業務代號"
    ["/admin/biz/u01/edit"]="編輯業務代號 u01"
    ["/admin/health"]="系統健康"
    ["/audit/query"]="稽核查詢"
    ["/api/health"]="API health"
)

echo ""
printf "%-30s %-8s %-8s %s\n" "Path" "HTTP" "Time(ms)" "說明"
printf "%-30s %-8s %-8s %s\n" "$(printf '%.0s-' {1..30})" "--------" "--------" "$(printf '%.0s-' {1..30})"

for path in "${!ROUTES[@]}"; do
    desc="${ROUTES[$path]}"
    result=$(curl -s -b "$COOKIE" -o /dev/null -w "%{http_code} %{time_total}" --max-time 5 "http://127.0.0.1:5000$path" 2>/dev/null || echo "000 0")
    code=$(echo "$result" | awk '{print $1}')
    time_total=$(echo "$result" | awk '{print $2}')
    time_ms=$(awk "BEGIN{printf \"%.0f\", $time_total * 1000}")
    if [[ "$code" =~ ^(200|302|303)$ ]]; then
        printf "${GREEN}%-30s %-8s %-8s %s${NC}\n" "$path" "$code" "$time_ms" "$desc"
    elif [[ "$code" =~ ^(401|403|404)$ ]]; then
        printf "${YELLOW}%-30s %-8s %-8s %s${NC}\n" "$path" "$code" "$time_ms" "$desc"
    else
        printf "${RED}%-30s %-8s %-8s %s${NC}\n" "$path" "$code" "$time_ms" "$desc"
    fi
done

rm -f "$COOKIE"

# === Step 10: error.log 摘要 ===
step "Step 10: /opt/portal/logs/error.log 最後 20 行"
tail -20 /opt/portal/logs/error.log 2>&1 | head -30

# === Step 11: DB 統計 ===
step "Step 11: DB 表筆數"
sudo -u postgres psql -d "$DB_NAME" -tAc "
SELECT 'businesscode: ' || count(*) FROM businesscode
UNION ALL SELECT 'batch: ' || count(*) FROM batch
UNION ALL SELECT 'batchfile: ' || count(*) FROM batchfile
UNION ALL SELECT 'auditlog: ' || count(*) FROM auditlog
UNION ALL SELECT 'portaluser: ' || count(*) FROM portaluser
UNION ALL SELECT 'sambapathhistory: ' || count(*) FROM sambapathhistory;
" 2>&1

MAIN_IP=$(ip -4 addr | grep -E 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}' | cut -d/ -f1)

echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║   v2.4.6 套完, 看上方診斷                                     ║${NC}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  瀏覽器: http://$MAIN_IP/   (Ctrl+F5 強制刷新)"
echo "  登入: 隨便 (dev_mode 還開著)"
echo ""
echo "  預期 KPI:"
echo "    啟用業務代號: 4   今日上傳: 2   今日 DENIED: 1   待簽批次: 1"
echo "  業務代號清單: 應看到 u01~u04"
echo "  我的待簽: 應看到 1 筆 (u01-20260520-1432)"
echo "  稽核查詢: 應看到 10 筆事件"
echo ""
echo "  Rollback: rm -rf $PORTAL_DIR/app/app && mv $PORTAL_DIR/app/app.bak.$TS $PORTAL_DIR/app/app && systemctl restart sf-portal"
echo ""
echo "  ⚠️  Step 9 任何 5xx 紅字 route, 截圖 + Step 10 error.log 貼上來"
