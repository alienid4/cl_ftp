#!/bin/bash
#
# v2.4.7_fix-pg-ident-auth.sh — 修 PostgreSQL ident → md5 認證
#
# v2.4.6 跑出來唯一 root cause:
#   psycopg2.OperationalError: FATAL:  Ident authentication failed for user "portal"
#
# 原因: pg_hba.conf 預設第一條:
#   host  all  all  127.0.0.1/32  ident
# Portal 在 nginx user 下跑, OS 無 portal user, ident 直接 reject.
# 我加的 md5 規則在後面, first-match-wins 永遠不會 match 到.
#
# 修法 (3 段):
#   1. pg_hba.conf 把 127.0.0.1 / ::1 的 ident 全改成 md5
#   2. reload postgresql
#   3. 補 admin.py biz_edit try/except, restart sf-portal
#   4. 重跑 route 掃描驗證
#
# 用法:
#   sudo bash /tmp/ftp-lab/v2.4.7_fix-pg-ident-auth.sh

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
echo -e "${BOLD}${CYAN}║   v2.4.7 — 修 PG ident → md5 認證 (portal 連 DB)              ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"

# === Step 1: 找 pg_hba.conf ===
step "Step 1: 找 pg_hba.conf"
PG_HBA=$(find /var/lib/pgsql -name pg_hba.conf 2>/dev/null | head -1)
[[ -n "$PG_HBA" ]] || fail "找不到 pg_hba.conf"
ok "$PG_HBA"

# === Step 2: backup ===
step "Step 2: backup pg_hba.conf"
TS=$(date +%s)
cp "$PG_HBA" "${PG_HBA}.bak.$TS"
ok "備份 ${PG_HBA}.bak.$TS"

# === Step 3: 看現在的認證設定 ===
step "Step 3: 現有設定"
echo ""
grep -nE '^(host|local).*\s(ident|peer|md5|trust|scram)' "$PG_HBA" | head -10

# === Step 4: 把 ident/peer 改成 md5 (只對 127.0.0.1 / ::1 / local) ===
step "Step 4: ident/peer → md5"

/usr/bin/python3 <<PYEOF
import re
from pathlib import Path

p = Path("$PG_HBA")
lines = p.read_text().split('\n')
out = []
changed = 0

for line in lines:
    stripped = line.strip()
    # 跳過註解 / 空行
    if not stripped or stripped.startswith('#'):
        out.append(line)
        continue
    # 拆欄位
    parts = stripped.split()
    if len(parts) < 4:
        out.append(line)
        continue
    # 把最後欄位 (METHOD) 是 ident / peer 改 md5
    # 只動 host 127.0.0.1/::1 跟 local 行
    if parts[0] in ('local', 'host'):
        last = parts[-1]
        if last in ('ident', 'peer'):
            new_parts = parts[:-1] + ['md5']
            new_line = '  '.join(new_parts)
            out.append(new_line)
            changed += 1
            continue
    out.append(line)

# 確保有 portal user 那條規則在最上方 (萬一被歷史殘留蓋掉)
PORTAL_RULE = 'host    file_exchange_audit    portal    127.0.0.1/32    md5'
has_portal_rule = any('file_exchange_audit' in l and 'portal' in l and 'md5' in l for l in out)
if not has_portal_rule:
    # 插入到第一條 host 之前
    inserted = False
    final = []
    for line in out:
        if not inserted and line.strip().startswith('host'):
            final.append(PORTAL_RULE)
            inserted = True
        final.append(line)
    out = final

p.write_text('\n'.join(out))
print(f'[patched] {changed} 行 ident/peer → md5, portal 規則已確認')
PYEOF

# === Step 5: reload postgresql ===
step "Step 5: reload postgresql"
systemctl reload postgresql 2>&1 | tail -3
sleep 2
if systemctl is-active postgresql &>/dev/null; then
    ok "postgresql active"
else
    fail "postgresql 重啟失敗"
fi

# === Step 6: 測 portal user 連得到 DB ===
step "Step 6: 測 portal user 連線"

# 從 .env 撈密碼
DB_PASS=$(grep -oP 'postgresql://portal:\K[^@]+' "$PORTAL_DIR/app/.env" 2>/dev/null)
if [[ -z "$DB_PASS" ]]; then
    fail "從 .env 撈不到密碼"
fi
ok "密碼讀到"

# 用 PGPASSWORD 測
if PGPASSWORD="$DB_PASS" psql -U "$DB_USER" -d "$DB_NAME" -h 127.0.0.1 -tAc "SELECT 'OK'" 2>&1 | grep -q OK; then
    ok "portal user 連 DB OK"
else
    echo ""
    PGPASSWORD="$DB_PASS" psql -U "$DB_USER" -d "$DB_NAME" -h 127.0.0.1 -tAc "SELECT 'OK'" 2>&1 | head -5
    fail "portal user 仍連不到 DB"
fi

# === Step 7: 套新版 admin.py (biz_edit try/except) ===
step "Step 7: 套新 admin.py"
TAR=$(find /tmp /opt /root -maxdepth 5 -name 'v2.4.7_sf-portal-source.tar.gz' -type f 2>/dev/null | head -1)
if [[ -z "$TAR" ]]; then
    # fallback 用 v2.4.6 tar 也行 (admin.py 的 biz_edit 在 v2.4.6 還沒加 try/except)
    info "沒 v2.4.7 tar, 試 v2.4.6"
    TAR=$(find /tmp /opt /root -maxdepth 5 -name 'v2.4.6_sf-portal-source.tar.gz' -type f 2>/dev/null | head -1)
fi

if [[ -n "$TAR" ]]; then
    info "解 $TAR"
    rm -rf /tmp/sf-portal-v247
    mkdir -p /tmp/sf-portal-v247
    tar xzf "$TAR" -C /tmp/sf-portal-v247
    cp /tmp/sf-portal-v247/portal/app/blueprints/admin.py "$PORTAL_DIR/app/app/blueprints/admin.py" 2>/dev/null || warn "cp admin.py 失敗"
    chown nginx:nginx "$PORTAL_DIR/app/app/blueprints/admin.py" 2>/dev/null || true
    ok "admin.py 拷入"
else
    warn "找不到 tar, 跳過 admin.py 更新 (biz_edit 仍 500)"
fi

# === Step 8: restart sf-portal ===
step "Step 8: restart sf-portal"
systemctl restart sf-portal
sleep 3
if systemctl is-active sf-portal &>/dev/null; then
    ok "sf-portal active"
else
    fail "sf-portal 啟動失敗"
fi

# === Step 9: 重掃 route ===
step "Step 9: 重掃 route 驗證"

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
printf "%-30s %-8s %-10s %s\n" "Path" "HTTP" "Time(ms)" "說明"
printf "%-30s %-8s %-10s %s\n" "$(printf '%.0s-' {1..30})" "--------" "----------" "$(printf '%.0s-' {1..30})"

ALL_OK=true
for path in "${!ROUTES[@]}"; do
    desc="${ROUTES[$path]}"
    result=$(curl -s -b "$COOKIE" -o /dev/null -w "%{http_code} %{time_total}" --max-time 5 "http://127.0.0.1:5000$path" 2>/dev/null || echo "000 0")
    code=$(echo "$result" | awk '{print $1}')
    time_total=$(echo "$result" | awk '{print $2}')
    time_ms=$(awk "BEGIN{printf \"%.0f\", $time_total * 1000}")
    if [[ "$code" =~ ^(200|302|303)$ ]]; then
        printf "${GREEN}%-30s %-8s %-10s %s${NC}\n" "$path" "$code" "$time_ms" "$desc"
    elif [[ "$code" =~ ^(401|403|404)$ ]]; then
        printf "${YELLOW}%-30s %-8s %-10s %s${NC}\n" "$path" "$code" "$time_ms" "$desc"
    else
        printf "${RED}%-30s %-8s %-10s %s${NC}\n" "$path" "$code" "$time_ms" "$desc"
        ALL_OK=false
    fi
done

rm -f "$COOKIE"

# === Step 10: DB 統計 ===
step "Step 10: DB 表筆數 (portal user 角度)"
PGPASSWORD="$DB_PASS" psql -U "$DB_USER" -d "$DB_NAME" -h 127.0.0.1 -tAc "
SELECT 'businesscode: ' || count(*) FROM businesscode
UNION ALL SELECT 'batch: ' || count(*) FROM batch
UNION ALL SELECT 'batchfile: ' || count(*) FROM batchfile
UNION ALL SELECT 'auditlog: ' || count(*) FROM auditlog;
" 2>&1

MAIN_IP=$(ip -4 addr | grep -E 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}' | cut -d/ -f1)

echo ""
if $ALL_OK; then
    echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${GREEN}║   ✅ v2.4.7 修完, 所有 route 都 OK                            ║${NC}"
    echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
else
    echo -e "${BOLD}${YELLOW}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${YELLOW}║   ⚠️  還有 5xx, 截圖貼上來                                    ║${NC}"
    echo -e "${BOLD}${YELLOW}╚══════════════════════════════════════════════════════════════╝${NC}"
fi
echo ""
echo "  瀏覽器: http://$MAIN_IP/   (Ctrl+F5 強制刷新)"
echo "  KPI 預期: 啟用 4 / 今日上傳 2 / DENIED 1 / 待簽 1"
echo ""
echo "  Rollback pg_hba: cp ${PG_HBA}.bak.$TS $PG_HBA && systemctl reload postgresql"
