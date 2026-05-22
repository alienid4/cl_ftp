#!/bin/bash
#
# fix_portal.sh v2.2.0 — 從零重建 Portal
#
# 對應 diagnose.sh 找到的 5 個問題:
#   - sf-portal.service 不存在
#   - Port 5000 沒監聽
#   - /opt/portal/app/wsgi.py 不存在
#   - /opt/portal/venv 不存在
#   - firewall 沒放行 80/5000
#
# 用法 (SF 完全離線版, 推薦):
#   sudo bash /tmp/ftp-lab/fix-portal-v2.2.0.sh
#
# 用法 (有 github 時, 即時下載):
#   curl -fsSL https://github.com/alienid4/cl_ftp/raw/main/deploy-rhel/fix_portal.sh | sudo bash
#
# 預期套件來源:
#   - EPEL Python (flask/werkzeug/gunicorn): /tmp/ftp-lab/sf-epel-pyrpms.tar.gz
#   - RHEL Python (psycopg2/cryptography):    dnf install (走公司 Satellite)
#   - Portal source:                         /tmp/ftp-lab/portal/ 或 /opt/sf/portal/
#

# 注意: 不用 set -e (避免某個 psql / systemctl 警告就 abort 整個 script)
# 各 step 自己用 || warn 處理錯誤
set -uo pipefail

VERSION="fix_portal v2.2.6 (2026-05-22)"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
BOLD='\033[1m'
step()  { echo ""; echo -e "${CYAN}=== $* ===${NC}"; }
ok()    { echo -e "${GREEN}[ok]${NC} $*"; }
warn()  { echo -e "${YELLOW}[warn]${NC} $*"; }
fail()  { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }

[[ $EUID -eq 0 ]] || fail "請 sudo: curl ... | sudo bash"

DB_PASS="${SF_DB_PASS:-changeme_$(openssl rand -hex 4)}"

echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║   $VERSION                              ║${NC}"
echo -e "${BOLD}${CYAN}║   (SF 離線, EPEL tar 從本地讀, RHEL 套件走 Satellite)        ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"

# === Step 1: 裝 Python 套件 ===
# 策略:
#   1a. 先 dnf 裝 RHEL BaseOS/AppStream 有的 (python3, pip, psycopg2, cryptography, requests)
#   1b. EPEL 套件 (flask, werkzeug, gunicorn, ldap...) 從 git 拉預打好的 tar 安裝
#       對應 GitHub Actions: .github/workflows/build-epel-pyrpms.yml
step "Step 1a: 裝 RHEL BaseOS/AppStream Python 套件 (含 EPEL 套件依賴)"

# 注意: 後面 EPEL flask/gunicorn/ldap3 需要這些 RHEL 套件做依賴:
#   - python3-jinja2     (flask 模板, AppStream)
#   - python3-packaging  (gunicorn, AppStream)
#   - python3-pyasn1     (ldap3, AppStream)
#   - python3-six        (一些套件需要, BaseOS)
dnf install -y \
    python3 python3-pip \
    python3-psycopg2 \
    python3-cryptography python3-requests \
    python3-jinja2 python3-packaging python3-pyasn1 \
    python3-six python3-setuptools 2>&1 | tail -10

# 確認 RHEL 套件可 import
for mod in psycopg2 cryptography; do
    if /usr/bin/python3 -c "import $mod" 2>/dev/null; then
        ok "python3 -c 'import $mod' OK (來自 RHEL repo)"
    else
        fail "$mod import 失敗 — 確認 AppStream repo enabled"
    fi
done

# === Step 1b: 找 EPEL Python RPM (3 種模式: 散檔 / tar / curl github) ===
step "Step 1b: 找 EPEL Python RPM"

EPEL_DIR="/tmp/sf-epel-pyrpms"
mkdir -p "$EPEL_DIR/rpms"

# 模式 1: 直接找散檔 *.rpm (USER 把 7 個 RPM 直接 scp 到資料夾)
RPM_DIR_CANDIDATES=(
    "/tmp/ftp-lab"                 # USER 軟體目錄 (推薦)
    "/tmp/ftp-lab/rpms"
    "/tmp/ftp-lab/epel-rpms"
    "/tmp/epel-rpms"
    "/opt/sf/epel-rpms"
)

EPEL_RPM_DIR=""
for d in "${RPM_DIR_CANDIDATES[@]}"; do
    if [[ -d "$d" ]] && ls "$d"/python3-flask-*.rpm &>/dev/null; then
        EPEL_RPM_DIR="$d"
        ok "找到散檔 RPM: $d/python3-*.rpm"

        # 拷貝時過濾重複下載的 (1).rpm 之類
        for f in "$d"/python3-*.rpm; do
            bn=$(basename "$f")
            # 跳過 "name (1).rpm" / "name (2).rpm" / "name-copy.rpm" 等變形
            if [[ "$bn" =~ \([0-9]+\)\.rpm$ ]] || [[ "$bn" =~ -copy\.rpm$ ]]; then
                warn "跳過重複下載: $bn"
                continue
            fi
            cp "$f" "$EPEL_DIR/rpms/" 2>/dev/null || true
        done
        break
    fi
done

# 模式 2: 找 tar (PC 跑 pack_local_rpms.ps1 打的)
if [[ -z "$EPEL_RPM_DIR" ]]; then
    EPEL_TAR_CANDIDATES=(
        "/tmp/ftp-lab/sf-epel-pyrpms.tar.gz"
        "/tmp/ftp-lab/release-zip/sf-epel-pyrpms.tar.gz"
        "/opt/sf/release-zip/sf-epel-pyrpms.tar.gz"
        "/opt/sf/sf-epel-pyrpms.tar.gz"
        "/tmp/sf-epel-pyrpms.tar.gz"
        "/root/sf-epel-pyrpms.tar.gz"
    )

    for p in "${EPEL_TAR_CANDIDATES[@]}"; do
        if [[ -f "$p" ]]; then
            ok "找到 tar: $p"
            cp "$p" "$EPEL_DIR/sf-epel-pyrpms.tar.gz"
            tar xzf "$EPEL_DIR/sf-epel-pyrpms.tar.gz" -C "$EPEL_DIR"
            # tar 內結構是 rpms/*.rpm
            [[ -d "$EPEL_DIR/rpms" ]] && EPEL_RPM_DIR="$EPEL_DIR/rpms"
            break
        fi
    done
fi

# 模式 3: 試 curl github (SF 有外網才會成功)
if [[ -z "$EPEL_RPM_DIR" ]]; then
    EPEL_TAR_URL="https://github.com/alienid4/cl_ftp/raw/main/release-zip/sf-epel-pyrpms.tar.gz"
    warn "本地沒散檔也沒 tar, 嘗試 curl github (10 秒 timeout)..."
    if curl -fsSL --max-time 10 -o "$EPEL_DIR/sf-epel-pyrpms.tar.gz" "$EPEL_TAR_URL"; then
        ok "github curl 成功"
        tar xzf "$EPEL_DIR/sf-epel-pyrpms.tar.gz" -C "$EPEL_DIR"
        [[ -d "$EPEL_DIR/rpms" ]] && EPEL_RPM_DIR="$EPEL_DIR/rpms"
    fi
fi

# 都沒找到 → 印 USER 操作步驟
if [[ -z "$EPEL_RPM_DIR" ]]; then
    fail "
EPEL Python RPM 找不到. 請按以下步驟之一:

[方法 A] 散檔 (你已下載 7 個 .rpm):
  把 7 個 python3-*.rpm scp 到 SF 的下列任一目錄:
$(printf '   - %s\n' "${RPM_DIR_CANDIDATES[@]}")

[方法 B] 預打 tar:
  PC: .\\pack_local_rpms.ps1 -SrcDir C:\\Temp\\epel-rpms
  PC: scp release-zip\\sf-epel-pyrpms.tar.gz root@<SF-IP>:/tmp/ftp-lab/
  (tar 內結構: rpms/*.rpm)

跑完重來: sudo bash $0
"
fi

# 確認 RPM 數量 + 必要套件
RPM_COUNT=$(ls "$EPEL_RPM_DIR"/*.rpm 2>/dev/null | wc -l)
if [[ "$RPM_COUNT" -lt 5 ]]; then
    fail "RPM 太少 ($RPM_COUNT), 至少要 7 個 (flask/werkzeug/gunicorn/itsdangerous/click/blinker/ldap3)"
fi
ok "找到 $RPM_COUNT 個 RPM 待安裝"
ls "$EPEL_RPM_DIR"/*.rpm | xargs -n1 basename | sed 's/^/    /'

cd "$EPEL_DIR"

# dnf install local RPMs
# 注意: 不能用 --disablerepo='*', 因為 EPEL RPMs 需要 RHEL AppStream 的依賴
#       (jinja2, packaging, pyasn1, six 等) - Step 1a 已裝
# 用 --enablerepo=* 讓 dnf 可以從 RHEL repo 解依賴
echo "[exec] dnf install local RPMs (from $EPEL_DIR/rpms)..."
dnf install -y --nogpgcheck --allowerasing "$EPEL_DIR"/rpms/*.rpm 2>&1 | tail -15 || {
    warn "dnf install 部分失敗, 嘗試 rpm -Uvh --force ..."
    rpm -Uvh --force --nodeps "$EPEL_DIR"/rpms/*.rpm 2>&1 | tail -10 || \
        fail "EPEL RPM 安裝失敗 — 看上方錯誤訊息哪個依賴缺"
}

# 確認 EPEL 來的模組可 import
MISSING=()
for mod in flask werkzeug; do
    if /usr/bin/python3 -c "import $mod" 2>/dev/null; then
        ok "python3 -c 'import $mod' OK (來自 EPEL local)"
    else
        MISSING+=("$mod")
        warn "$mod import 失敗"
    fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
    fail "EPEL 核心套件沒裝齊: ${MISSING[*]}"
fi

ok "全部 Python 套件就緒 (RHEL repo + EPEL tar)"

# === Step 2: 拷 Portal 程式碼 ===
step "Step 2: 拷 Portal source 到 /opt/portal/app"

mkdir -p /opt/portal/{app,logs,scripts}

# 找 Portal source (USER 軟體目錄優先)
PORTAL_SRC_CANDIDATES=(
    "/tmp/ftp-lab/portal"
    "/tmp/ftp-lab/cl_ftp/portal"
    "/opt/sf/portal"
)

PORTAL_SRC=""
for d in "${PORTAL_SRC_CANDIDATES[@]}"; do
    if [[ -d "$d" ]] && [[ -n "$(ls -A "$d" 2>/dev/null)" ]]; then
        PORTAL_SRC="$d"
        break
    fi
done

if [[ -n "$PORTAL_SRC" ]]; then
    cp -r "$PORTAL_SRC"/* /opt/portal/app/
    ok "拷貝 $PORTAL_SRC/* -> /opt/portal/app/"
else
    fail "Portal source 找不到, 請 scp 過去:
  scp -r portal/ root@<SF-IP>:/tmp/ftp-lab/portal

或從以下任一位置放:
$(printf '   - %s\n' "${PORTAL_SRC_CANDIDATES[@]}")"
fi

# === Patch wsgi.py 確保有 module-level `app` (gunicorn import 用) ===
WSGI_FILE="/opt/portal/app/wsgi.py"
if [[ -f "$WSGI_FILE" ]]; then
    # 找 module-level (非縮排) "app = " 賦值
    if ! grep -qE '^app *= *create_app' "$WSGI_FILE"; then
        warn "wsgi.py 沒有 module-level 'app' (Windows waitress 版?), 自動 patch"
        cp "$WSGI_FILE" "$WSGI_FILE.bak.$(date +%Y%m%d_%H%M%S)"

        cat > "$WSGI_FILE" <<'WSGI_EOF'
"""
SF Portal — WSGI Entry Point (auto-patched by fix_portal.sh)
Linux + gunicorn: import wsgi:app
"""
from app import create_app

app = create_app()

if __name__ == '__main__':
    try:
        from waitress import serve
        serve(app, host='127.0.0.1', port=5000, threads=8)
    except ImportError:
        app.run(host='127.0.0.1', port=5000, debug=False)
WSGI_EOF
        chown "$RUN_USER:$RUN_USER" "$WSGI_FILE"
        ok "wsgi.py patched (備份在 $WSGI_FILE.bak.*)"
    else
        ok "wsgi.py 已是 gunicorn-friendly (module-level app)"
    fi
fi

# 確認 import 通 (在跑 gunicorn 前先測, 失敗早點抓到)
echo "[exec] 測 wsgi:app 能不能 import ..."
if sudo -u "$RUN_USER" /usr/bin/python3 -c "
import sys
sys.path.insert(0, '/opt/portal/app')
import wsgi
assert hasattr(wsgi, 'app'), 'wsgi has no app attribute'
print('OK: wsgi.app =', type(wsgi.app).__name__)
" 2>&1; then
    ok "wsgi:app 可以 import"
else
    warn "wsgi:app import 失敗 — 看上方 Python traceback"
    warn "gunicorn 啟動可能會失敗, 但繼續往下試"
fi

# 用 nginx user 跑 (跟 nginx 同 uid 較簡單; 也可改 sf-portal)
if id -u nginx &>/dev/null; then
    RUN_USER="nginx"
elif id -u portal &>/dev/null; then
    RUN_USER="portal"
else
    useradd -r -s /sbin/nologin -d /opt/portal portal
    RUN_USER="portal"
fi
ok "RUN_USER = $RUN_USER"

chown -R "$RUN_USER:$RUN_USER" /opt/portal

# === Step 3: 寫 appsettings.json ===
step "Step 3: 寫 Portal appsettings.json"

# 切到 /tmp 避免 postgres user 沒權限 cd 當前目錄
cd /tmp

# === DB + user 永遠跑 (idempotent), 不關 appsettings.json 在不在 ===

# 1. 建 database
if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='file_exchange_audit'" 2>/dev/null | grep -q 1; then
    if sudo -u postgres psql -c "CREATE DATABASE file_exchange_audit;" 2>&1 | tail -3; then
        ok "Database file_exchange_audit 建立"
    else
        warn "CREATE DATABASE 失敗, 看上面訊息"
    fi
else
    ok "Database file_exchange_audit 已存在"
fi

# 2. 重新讀 DB 密碼 (如果 appsettings.json 已存在, 用裡面的; 否則用新生的)
if [[ -f /opt/portal/app/appsettings.json ]]; then
    EXISTING_PASS=$(grep -oP 'postgresql://portal:\K[^@]+' /opt/portal/app/appsettings.json 2>/dev/null || true)
    if [[ -n "$EXISTING_PASS" ]]; then
        DB_PASS="$EXISTING_PASS"
        ok "用既有 appsettings.json 內的 DB 密碼"
    fi
fi

# 3. 建 / 更新 portal user
sudo -u postgres psql <<EOF 2>&1 | tail -5
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_user WHERE usename = 'portal') THEN
        CREATE USER portal WITH PASSWORD '$DB_PASS';
    ELSE
        ALTER USER portal WITH PASSWORD '$DB_PASS';
    END IF;
END \$\$;

GRANT ALL PRIVILEGES ON DATABASE file_exchange_audit TO portal;
ALTER DATABASE file_exchange_audit OWNER TO portal;
EOF
ok "Portal user 建立 / 更新"

# 4. 寫 appsettings.json (如果還沒)
if [[ ! -f /opt/portal/app/appsettings.json ]]; then
    cat > /opt/portal/app/appsettings.json <<EOF
{
    "DATABASE_URL": "postgresql://portal:$DB_PASS@127.0.0.1:5432/file_exchange_audit",
    "PORTAL_PORT": 5000,
    "DATA_ROOT": "/data/exchange",
    "LOG_DIR": "/opt/portal/logs",
    "AD_DOMAIN": "corp.local",
    "SECRET_KEY": "$(openssl rand -hex 32)"
}
EOF
    chmod 640 /opt/portal/app/appsettings.json
    chown "$RUN_USER:$RUN_USER" /opt/portal/app/appsettings.json
    ok "appsettings.json 寫入"
else
    ok "appsettings.json 已存在, skip"
fi

# 5. 套 schema (永遠嘗試)
if [[ -f /opt/sf/sql/01_create_db_postgres.sql ]]; then
    sudo -u postgres psql -d file_exchange_audit < /opt/sf/sql/01_create_db_postgres.sql 2>&1 | tail -3 || warn "schema 套用部分失敗 (可能 DB 不存在)"
    ok "Schema 套用嘗試完成"
elif [[ -f /tmp/ftp-lab/sql/01_create_db_postgres.sql ]]; then
    sudo -u postgres psql -d file_exchange_audit < /tmp/ftp-lab/sql/01_create_db_postgres.sql 2>&1 | tail -3 || warn "schema 套用部分失敗"
    ok "Schema 套用嘗試完成 (from /tmp/ftp-lab/sql/)"
else
    warn "找不到 schema SQL 檔 (Portal 第一次跑時會自動建表)"
fi

# 修 pg_hba.conf 允許 portal 連
PG_HBA=$(find /var/lib/pgsql /etc/postgresql -name pg_hba.conf 2>/dev/null | head -1)
if [[ -n "$PG_HBA" ]] && ! grep -q "host.*file_exchange_audit.*portal.*127.0.0.1" "$PG_HBA" 2>/dev/null; then
    echo "host    file_exchange_audit    portal    127.0.0.1/32    md5" >> "$PG_HBA" || warn "寫 pg_hba.conf 失敗"
    systemctl reload postgresql 2>&1 | tail -2 || warn "reload postgresql 失敗 (繼續)"
    ok "pg_hba.conf 允許 portal 連 (127.0.0.1)"
fi

# === Step 4: 寫 systemd unit ===
step "Step 4: 寫 systemd unit /etc/systemd/system/sf-portal.service"

# 判斷: 動態抓 gunicorn 真實 binary 路徑 (EPEL 21.2.0 是 /usr/bin/gunicorn, 不是 gunicorn-3)
GUNICORN_BIN=""
for candidate in /usr/bin/gunicorn /usr/bin/gunicorn-3 /usr/local/bin/gunicorn; do
    if [[ -x "$candidate" ]]; then
        GUNICORN_BIN="$candidate"
        break
    fi
done

# 也試 PATH 上的
if [[ -z "$GUNICORN_BIN" ]]; then
    GUNICORN_BIN=$(command -v gunicorn 2>/dev/null || command -v gunicorn-3 2>/dev/null || echo "")
fi

if [[ -n "$GUNICORN_BIN" ]] && /usr/bin/python3 -c "import gunicorn" 2>/dev/null; then
    EXEC_LINE="ExecStart=$GUNICORN_BIN --workers 3 --bind 127.0.0.1:5000 --access-logfile /opt/portal/logs/access.log --error-logfile /opt/portal/logs/error.log wsgi:app"
    SERVER_DESC="gunicorn ($GUNICORN_BIN)"
else
    EXEC_LINE='ExecStart=/usr/bin/python3 -m flask run --host=127.0.0.1 --port=5000 --no-debugger --no-reload'
    SERVER_DESC="Flask built-in werkzeug (找不到 gunicorn binary)"
fi
ok "WSGI server: $SERVER_DESC"

cat > /etc/systemd/system/sf-portal.service <<EOF
[Unit]
Description=SF File Exchange Portal ($SERVER_DESC)
After=network.target postgresql.service

[Service]
Type=simple
User=$RUN_USER
Group=$RUN_USER
WorkingDirectory=/opt/portal/app
Environment="PYTHONPATH=/opt/portal/app"
Environment="FLASK_APP=wsgi:app"
Environment="FLASK_ENV=production"
$EXEC_LINE
Restart=always
RestartSec=10

StandardOutput=append:/opt/portal/logs/portal-stdout.log
StandardError=append:/opt/portal/logs/portal-stderr.log

[Install]
WantedBy=multi-user.target
EOF
ok "sf-portal.service 寫入"

systemctl daemon-reload

# === Step 5: 防火牆 ===
step "Step 5: 防火牆放行 80 (5000 限本機, 不對外)"

if systemctl is-active firewalld &>/dev/null; then
    firewall-cmd --permanent --add-service=http 2>&1 | tail -2
    firewall-cmd --reload 2>&1 | tail -2
    ok "防火牆放行 http (80)"
fi

# === Step 6: 啟動 + 等 + 驗證 ===
step "Step 6: 啟動 sf-portal"

systemctl enable sf-portal 2>&1 | tail -2
systemctl restart sf-portal

echo "等 sf-portal 起來 (最多 30 秒)..."
PORTAL_OK=false
for i in $(seq 1 15); do
    if systemctl is-active sf-portal &>/dev/null; then
        code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 http://localhost:5000/ 2>/dev/null || echo 000)
        if [[ "$code" =~ ^(200|302|401|403)$ ]]; then
            PORTAL_OK=true
            ok "Portal 起來 (HTTP $code)"
            break
        fi
    fi
    sleep 2
done

# === 結果 ===
echo ""
if $PORTAL_OK; then
    MAIN_IP=$(ip -4 addr | grep -E 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}' | cut -d/ -f1)
    echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${GREEN}║   ✅ Portal 已修好, 可給 USER 測試                            ║${NC}"
    echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "  Portal: http://$MAIN_IP/        (nginx 反代 80 → 5000)"
    echo "  Direct: http://$MAIN_IP:5000/   (本機 debug)"
else
    echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║   ❌ Portal 仍沒起來, 看 log                                  ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "=== systemctl status sf-portal ==="
    systemctl status sf-portal --no-pager -l 2>&1 | tail -20
    echo ""
    echo "=== journalctl -u sf-portal (最後 30 行) ==="
    journalctl -u sf-portal -n 30 --no-pager 2>&1
    echo ""
    echo "=== /opt/portal/logs/portal-stderr.log ==="
    tail -30 /opt/portal/logs/portal-stderr.log 2>&1
    echo ""
    echo "→ 看上面錯誤訊息, 截圖貼給 Claude 找下一步"
    exit 1
fi
