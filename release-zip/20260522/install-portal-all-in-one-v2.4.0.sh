#!/bin/bash
#
# install_portal_all_in_one v2.4.0 — SF Portal 一次裝完
#
# 修正 v2.3.x 一路修一次一個錯的問題.
# v2.4.0 是 pre-flight 完整掃描後一次解決所有已知問題的版本.
#
# 變更於 v2.3.8:
#   1. config.py 走 dotenv 不走 appsettings.json → 寫 .env 不寫 .json
#   2. .env 內 DB_CONNECTION_STRING 必須是 PG URL, 不是 MSSQL 字串
#   3. .env 內 DATA_EXCHANGE_ROOT / PORTAL_LOG_DIR 設 Linux 路徑
#   4. dotenv 套件衝突: 清掉 stub 再 unzip python_dotenv wheel
#   5. db.py 加 SELECT TOP N → LIMIT N 翻譯 (走新 tar.gz)
#   6. PG schema 重寫對齊 caller (auditlog/businesscode/batchfile 等 lowercase no-underscore)
#   7. 自動跑 schema (新增 Step 6b)
#
# 用法 (SF 主機):
#   sudo bash /tmp/ftp-lab/install-portal-all-in-one-v2.4.0.sh
#
# 前置 (PC 端先做完):
#   1. 7 個 EPEL RPM scp 到 /tmp/ftp-lab/
#   2. 4 個 PyPI wheel scp 到 /tmp/ftp-lab/
#   3. sf-portal-source-v2.4.0.tar.gz scp 到 /tmp/ftp-lab/
#
# 本腳本自動搜尋上述檔. 找不到會明確告訴你缺什麼.

set -uo pipefail

VERSION="install_portal_all_in_one v2.4.0 (2026-05-22)"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
BOLD='\033[1m'
step()  { echo ""; echo -e "${CYAN}=== $* ===${NC}"; }
ok()    { echo -e "${GREEN}[ok]${NC} $*"; }
warn()  { echo -e "${YELLOW}[warn]${NC} $*"; }
fail()  { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }
info()  { echo -e "${CYAN}[info]${NC} $*"; }

[[ $EUID -eq 0 ]] || fail "請 sudo 跑本腳本"

echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║   $VERSION              ║${NC}"
echo -e "${BOLD}${CYAN}║   Pre-flight 完整掃描版, 一次解所有已知問題                  ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"

# === 環境變數 (可覆寫) ===
SEARCH_ROOTS=(
    "/tmp"
    "/tmp/ftp-lab"
    "/tmp/ftp-lab/rpms"
    "/tmp/ftp-lab/wheels"
    "/tmp/rpms"
    "/tmp/wheels"
    "/root"
    "/opt/sf"
)

PORTAL_SRC_CANDIDATES=(
    "/tmp/ftp-lab/portal"
    "/tmp/epel-rpms/portal"
    "/tmp/portal"
    "/tmp/sf/portal"
    "/opt/sf/portal"
    "/opt/portal-src"
)

DB_PASS="${SF_DB_PASS:-changeme_$(openssl rand -hex 4)}"
PORTAL_DIR="/opt/portal"
SITE_PACKAGES="/usr/lib/python3.9/site-packages"
DB_NAME="file_exchange_audit"
DB_USER="portal"

# === Step 0: 環境檢查 ===
step "Step 0: 環境檢查"

if grep -qE 'release 9' /etc/redhat-release 2>/dev/null; then
    ok "OS: $(cat /etc/redhat-release)"
else
    warn "不是 RHEL 9, 可能不相容"
fi

# === Step 1: 找全部需要的檔 ===
step "Step 1: 自動搜尋 /tmp 等位置的軟體檔"

find_file() {
    local pattern="$1"
    for d in "${SEARCH_ROOTS[@]}"; do
        [[ -d "$d" ]] || continue
        local f
        f=$(find "$d" -maxdepth 5 -name "$pattern" -type f 2>/dev/null \
            | grep -vE '\([0-9]+\)\.' \
            | head -1)
        if [[ -n "$f" ]]; then
            echo "$f"
            return 0
        fi
    done
    return 1
}

dump_tmp_structure() {
    echo ""
    echo "=== /tmp/ftp-lab/ 內容 (debug) ==="
    ls -la /tmp/ftp-lab/ 2>&1 | head -30
    echo ""
    echo "=== find /tmp -name '*.rpm' ==="
    find /tmp -maxdepth 5 -name '*.rpm' 2>/dev/null | head -30
    echo ""
    echo "=== find /tmp -name '*.whl' ==="
    find /tmp -maxdepth 5 -name '*.whl' 2>/dev/null | head -10
    echo ""
    echo "=== find /tmp -name '*.tar.gz' ==="
    find /tmp -maxdepth 5 -name '*.tar.gz' 2>/dev/null | head -10
    echo ""
}

# 7 個 EPEL RPM
REQUIRED_RPMS=(
    "python3-flask-*.rpm"
    "python3-werkzeug-*.rpm"
    "python3-gunicorn-*.rpm"
    "python3-itsdangerous-*.rpm"
    "python3-click-*.rpm"
    "python3-blinker-*.rpm"
    "python3-ldap3-*.rpm"
)

# 4 個 PyPI wheel
REQUIRED_WHEELS=(
    "Flask_Login-*.whl"
    "cachelib-*.whl"
    "flask_session-*.whl"
    "python_dotenv-*.whl"
)

declare -A FOUND_RPMS
declare -A FOUND_WHEELS
MISSING_FILES=()

for pat in "${REQUIRED_RPMS[@]}"; do
    f=$(find_file "$pat")
    if [[ -n "$f" ]]; then
        FOUND_RPMS["$pat"]="$f"
        ok "RPM: $f"
    else
        warn "缺 $pat"
        MISSING_FILES+=("$pat")
    fi
done

for pat in "${REQUIRED_WHEELS[@]}"; do
    f=$(find_file "$pat")
    if [[ -n "$f" ]]; then
        FOUND_WHEELS["$pat"]="$f"
        ok "Wheel: $f"
    else
        warn "缺 $pat"
        MISSING_FILES+=("$pat")
    fi
done

# 找 Portal source — 優先 v2.4.0 tar
PORTAL_SRC=""
PORTAL_TAR=$(find /tmp /opt /root -maxdepth 5 -name 'sf-portal-source-v2.4.0.tar.gz' -type f 2>/dev/null | head -1)
if [[ -n "$PORTAL_TAR" ]]; then
    info "找到 v2.4.0 portal tar: $PORTAL_TAR"
    rm -rf /tmp/sf-portal-extracted
    mkdir -p /tmp/sf-portal-extracted
    tar xzf "$PORTAL_TAR" -C /tmp/sf-portal-extracted
    if [[ -d /tmp/sf-portal-extracted/portal ]]; then
        PORTAL_SRC="/tmp/sf-portal-extracted/portal"
    else
        PORTAL_SRC="/tmp/sf-portal-extracted"
    fi
    ok "Portal source (v2.4.0 extracted): $PORTAL_SRC"
fi

# Fallback: 候選路徑 + 動態 find wsgi.py
if [[ -z "$PORTAL_SRC" ]]; then
    for d in "${PORTAL_SRC_CANDIDATES[@]}"; do
        if [[ -d "$d" ]] && [[ -f "$d/wsgi.py" || -d "$d/app" ]]; then
            PORTAL_SRC="$d"
            warn "Portal source (候選, 不是 v2.4.0): $d"
            break
        fi
    done
fi

if [[ -z "$PORTAL_SRC" ]]; then
    info "Portal source 沒找到, 動態 find wsgi.py ..."
    while IFS= read -r wsgi_file; do
        parent=$(dirname "$wsgi_file")
        if [[ -d "$parent/app" ]]; then
            PORTAL_SRC="$parent"
            warn "Portal source (find, 不是 v2.4.0): $PORTAL_SRC"
            break
        fi
    done < <(find /tmp /opt /root /home -maxdepth 6 -name 'wsgi.py' -type f 2>/dev/null)
fi

# Fallback: 找任何 portal*.tar.gz
if [[ -z "$PORTAL_SRC" ]]; then
    info "找其他 portal tar.gz ..."
    PORTAL_TAR=$(find /tmp /opt /root -maxdepth 5 \( -name 'sf-portal-source*.tar.gz' -o -name 'portal*.tar.gz' \) -type f 2>/dev/null | head -1)
    if [[ -n "$PORTAL_TAR" ]]; then
        warn "找到 (不是 v2.4.0): $PORTAL_TAR"
        rm -rf /tmp/sf-portal-extracted
        mkdir -p /tmp/sf-portal-extracted
        tar xzf "$PORTAL_TAR" -C /tmp/sf-portal-extracted
        if [[ -d /tmp/sf-portal-extracted/portal ]]; then
            PORTAL_SRC="/tmp/sf-portal-extracted/portal"
        else
            PORTAL_SRC="/tmp/sf-portal-extracted"
        fi
    fi
fi

if [[ -z "$PORTAL_SRC" ]]; then
    MISSING_FILES+=("sf-portal-source-v2.4.0.tar.gz")
fi

# 找 SQL schema
SCHEMA_SQL=""
SCHEMA_SQL=$(find /tmp /opt /root -maxdepth 6 -name '01_create_db_postgres*.sql' -type f 2>/dev/null | head -1)
if [[ -z "$SCHEMA_SQL" && -n "$PORTAL_SRC" ]]; then
    # tar.gz 內可能含 sql/
    SCHEMA_SQL=$(find /tmp/sf-portal-extracted -maxdepth 4 -name '01_create_db_postgres*.sql' 2>/dev/null | head -1)
fi
if [[ -n "$SCHEMA_SQL" ]]; then
    ok "Schema SQL: $SCHEMA_SQL"
else
    warn "找不到 01_create_db_postgres.sql — Step 6b 會跳過 schema 套用"
fi

if [[ ${#MISSING_FILES[@]} -gt 0 ]]; then
    echo ""
    warn "缺 ${#MISSING_FILES[@]} 個必要檔:"
    printf '  - %s\n' "${MISSING_FILES[@]}"
    dump_tmp_structure
    fail "
請確認上述檔案都在 /tmp/ 任一子目錄, 然後重跑.
下載清單見 notes/20260522/v2.4.0_preflight-checklist.md"
fi

ok "全部檔案找齊"

# === Step 2: dnf install RHEL Python 依賴 ===
step "Step 2: 裝 RHEL AppStream 套件 (Python + nginx + postgresql + firewalld)"

dnf install -y \
    python3 \
    python3-psycopg2 python3-cryptography python3-requests \
    python3-jinja2 python3-packaging python3-pyasn1 \
    python3-six python3-setuptools unzip \
    nginx \
    postgresql postgresql-server postgresql-contrib \
    firewalld policycoreutils-python-utils 2>&1 | tail -10

for mod in psycopg2 cryptography jinja2; do
    if /usr/bin/python3 -c "import $mod" 2>/dev/null; then
        ok "import $mod OK"
    else
        warn "import $mod 失敗"
    fi
done

# === Step 2a: 初始化 PostgreSQL ===
if [[ ! -f /var/lib/pgsql/data/PG_VERSION ]]; then
    info "PostgreSQL 還沒 initdb, 跑 postgresql-setup --initdb"
    /usr/bin/postgresql-setup --initdb 2>&1 | tail -3 || warn "initdb 失敗"
fi

systemctl enable --now postgresql 2>&1 | tail -2 || warn "postgresql enable 失敗"
sleep 2
if systemctl is-active postgresql &>/dev/null; then
    ok "postgresql active"
else
    fail "postgresql 沒起來, 看 journalctl -u postgresql"
fi

# === Step 2b: 啟 nginx + firewalld ===
systemctl enable --now firewalld 2>&1 | tail -2 || warn "firewalld 啟動失敗"
systemctl enable --now nginx 2>&1 | tail -2 || warn "nginx 啟動失敗"
ok "nginx / firewalld 啟動"

# === Step 3: 裝 EPEL RPM ===
step "Step 3: 裝 EPEL Python RPM (rpm -Uvh --force --nodeps)"

RPM_LIST=()
for pat in "${REQUIRED_RPMS[@]}"; do
    [[ -n "${FOUND_RPMS[$pat]:-}" ]] && RPM_LIST+=("${FOUND_RPMS[$pat]}")
done

echo "[exec] rpm -Uvh --force --nodeps ${#RPM_LIST[@]} 個 RPM ..."
rpm -Uvh --force --nodeps "${RPM_LIST[@]}" 2>&1 | tail -15 || warn "rpm 部分失敗 (可能已裝過)"

for mod in flask werkzeug gunicorn; do
    if /usr/bin/python3 -c "import $mod" 2>/dev/null; then
        ok "import $mod OK (來自 EPEL RPM)"
    else
        warn "import $mod 失敗"
    fi
done

# === Step 4: 清掉所有 dotenv 殘留 + unzip wheel ===
step "Step 4: 清舊 dotenv 殘留 + unzip wheel 到 $SITE_PACKAGES"

# 4a: 清 /usr/local 殘留 (舊 pip install)
rm -rf /usr/local/lib/python3.9/site-packages/flask_login* 2>/dev/null
rm -rf /usr/local/lib/python3.9/site-packages/Flask_Login* 2>/dev/null
rm -rf /usr/local/lib/python3.9/site-packages/flask_session* 2>/dev/null
rm -rf /usr/local/lib/python3.9/site-packages/cachelib* 2>/dev/null
rm -rf /usr/local/lib/python3.9/site-packages/dotenv* 2>/dev/null
rm -rf /usr/local/lib/python3.9/site-packages/python_dotenv* 2>/dev/null

# 4b: 清 /usr/lib 內可能存在的 dotenv stub (v2.3.9 學到的)
rm -rf "$SITE_PACKAGES"/dotenv* 2>/dev/null
rm -rf "$SITE_PACKAGES"/python_dotenv* 2>/dev/null
rm -f  "$SITE_PACKAGES"/dotenv.py 2>/dev/null
ok "清掉所有舊 dotenv 殘留"

# 4c: unzip 4 個 wheel
for pat in "${REQUIRED_WHEELS[@]}"; do
    whl="${FOUND_WHEELS[$pat]:-}"
    [[ -n "$whl" ]] || continue
    echo "[exec] unzip $(basename "$whl")"
    unzip -o -q "$whl" -d "$SITE_PACKAGES/" 2>&1 | tail -3 || warn "unzip $whl 失敗"
done

# 4d: 驗證 — 不只是 import, 而是真的能拿到關鍵 symbol
declare -A IMPORT_TESTS=(
    ["flask_login"]="from flask_login import LoginManager"
    ["flask_session"]="from flask_session import Session"
    ["cachelib"]="import cachelib; cachelib.FileSystemCache"
    ["dotenv"]="from dotenv import load_dotenv"
)

ALL_OK=true
for mod in "${!IMPORT_TESTS[@]}"; do
    test_cmd="${IMPORT_TESTS[$mod]}"
    if /usr/bin/python3 -c "$test_cmd" 2>/dev/null; then
        ok "$test_cmd → OK"
    else
        warn "$test_cmd → 失敗"
        ALL_OK=false
    fi
done

# 確認 nginx user 存在
if ! id -u nginx &>/dev/null; then
    useradd -r -s /sbin/nologin nginx 2>/dev/null || true
fi

# 修權限讓 nginx user 也能讀
chmod -R o+rX "$SITE_PACKAGES/" 2>/dev/null

# 4e: nginx user 也驗
echo ""
info "nginx user import 驗證..."
for mod in "${!IMPORT_TESTS[@]}"; do
    test_cmd="${IMPORT_TESTS[$mod]}"
    if sudo -u nginx /usr/bin/python3 -c "$test_cmd" 2>/dev/null; then
        ok "(nginx) $test_cmd → OK"
    else
        warn "(nginx) $test_cmd → 失敗"
        ALL_OK=false
    fi
done

$ALL_OK || warn "有 import 失敗 — Portal 可能起不來, 看上面哪行 fail"

# === Step 5: 拷 Portal source 到 /opt/portal/app ===
step "Step 5: 拷 Portal source"

mkdir -p "$PORTAL_DIR"/{logs,scripts,backups}

if [[ -d "$PORTAL_DIR/app" ]]; then
    warn "清掉舊 /opt/portal/app/ (避免 patch 殘留)"
    rm -rf "$PORTAL_DIR/app"
fi
mkdir -p "$PORTAL_DIR/app"

cp -r "$PORTAL_SRC"/* "$PORTAL_DIR/app/" 2>&1 | tail -3
ok "拷 $PORTAL_SRC/* -> $PORTAL_DIR/app/ (fresh)"

# 判斷 RUN_USER
if id -u nginx &>/dev/null; then
    RUN_USER="nginx"
else
    useradd -r -s /sbin/nologin -d "$PORTAL_DIR" portal 2>/dev/null || true
    RUN_USER="portal"
fi
ok "RUN_USER = $RUN_USER"

# 驗 wsgi.py 確實有 module-level app
if [[ -f "$PORTAL_DIR/app/wsgi.py" ]]; then
    if grep -qE '^app[[:space:]]*=' "$PORTAL_DIR/app/wsgi.py"; then
        ok "wsgi.py 有 module-level app"
    else
        warn "wsgi.py 沒 module-level app, 確認 sf-portal-source-v2.4.0.tar.gz 是新版"
    fi
else
    fail "$PORTAL_DIR/app/wsgi.py 不存在, Portal source 缺檔"
fi

# 驗 db.py 是 psycopg2 (不是 pyodbc)
if grep -q '^import psycopg2' "$PORTAL_DIR/app/app/db.py" 2>/dev/null; then
    ok "db.py 是 psycopg2 版 (v2.3.8+)"
else
    fail "db.py 不是 psycopg2 版 — Portal source 是舊版"
fi

# 驗 db.py 有 TOP→LIMIT 翻譯 (v2.4.0)
if grep -q 'SELECT.*TOP.*LIMIT' "$PORTAL_DIR/app/app/db.py" 2>/dev/null; then
    ok "db.py 含 TOP→LIMIT 翻譯 (v2.4.0)"
else
    warn "db.py 沒有 TOP→LIMIT 翻譯 — audit_helper.search_audit 會失敗 (但不影響 portal 啟動)"
fi

# === Step 6: PostgreSQL DB + user ===
step "Step 6: 建 DB + portal user"

cd /tmp

if ! systemctl is-active postgresql &>/dev/null; then
    systemctl enable --now postgresql 2>&1 | tail -3 || true
fi

# 1. 建 database
if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" 2>/dev/null | grep -q 1; then
    sudo -u postgres psql -c "CREATE DATABASE $DB_NAME;" 2>&1 | tail -3
    ok "DB $DB_NAME 建立"
else
    ok "DB $DB_NAME 已存在"
fi

# 2. 建/更新 portal user
sudo -u postgres psql <<EOF 2>&1 | tail -3
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_user WHERE usename = '$DB_USER') THEN
        CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';
    ELSE
        ALTER USER $DB_USER WITH PASSWORD '$DB_PASS';
    END IF;
END \$\$;
GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;
ALTER DATABASE $DB_NAME OWNER TO $DB_USER;
EOF
ok "Portal user 建立 / 更新, 密碼: $DB_PASS"

# 3. 修 pg_hba.conf 允許 portal 連 127.0.0.1
PG_HBA=$(find /var/lib/pgsql -name pg_hba.conf 2>/dev/null | head -1)
if [[ -n "$PG_HBA" ]] && ! grep -q "host.*$DB_NAME.*$DB_USER.*127.0.0.1" "$PG_HBA"; then
    echo "host    $DB_NAME    $DB_USER    127.0.0.1/32    md5" >> "$PG_HBA"
    systemctl reload postgresql 2>&1 | tail -2 || warn "reload postgresql 失敗"
    ok "pg_hba.conf 允許 portal 連"
fi

# === Step 6b: 套用 schema ===
step "Step 6b: 套用 Schema (建表)"
if [[ -n "$SCHEMA_SQL" ]]; then
    sudo -u postgres psql -d "$DB_NAME" -f "$SCHEMA_SQL" 2>&1 | tail -10
    # 驗證關鍵表
    TABLE_COUNT=$(sudo -u postgres psql -tAc "SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_name IN ('auditlog','businesscode','batch','batchfile','portaluser','sambapathhistory')" "$DB_NAME" 2>/dev/null)
    if [[ "$TABLE_COUNT" -ge 6 ]]; then
        ok "Schema 套用成功 ($TABLE_COUNT/6 個關鍵表存在)"
    else
        warn "Schema 套用後只看到 $TABLE_COUNT/6 個表"
    fi
    # GRANT 給 portal user (剛建的表 owner 是 postgres)
    sudo -u postgres psql -d "$DB_NAME" <<EOF 2>&1 | tail -3
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $DB_USER;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO $DB_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO $DB_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO $DB_USER;
EOF
    ok "Portal user 對所有表的權限授予"
else
    warn "沒 schema SQL, 跳過 (Portal 啟動會起來但功能會壞)"
fi

# === Step 6c: 寫 .env (config.py 走 dotenv 不是 appsettings.json) ===
step "Step 6c: 寫 /opt/portal/app/.env"

cat > "$PORTAL_DIR/app/.env" <<EOF
# SF Portal v2.4.0 自動產生 — $(date '+%Y-%m-%d %H:%M:%S')
# 不要 commit 到 git

# Flask
FLASK_ENV=production
SECRET_KEY=$(openssl rand -hex 32)
SESSION_TIMEOUT_MIN=30
DEBUG=false
VERBOSE_LOG=false

# DB (PostgreSQL URL, 不是 MSSQL ODBC 字串)
DB_MODE=Express
DB_CONNECTION_STRING=postgresql://$DB_USER:$DB_PASS@127.0.0.1:5432/$DB_NAME

# AD / LDAP (USER 自行修改成公司 domain)
AD_SERVER=ldap://corp-dc01.corp.local
AD_BASE_DN=DC=corp,DC=local
AD_DOMAIN=CORP
AD_BIND_USER=
AD_BIND_PASS=

# Mail (USER 自行修改)
SMTP_SERVER=mail-relay.corp.local
SMTP_PORT=25
SMTP_USE_TLS=false
SMTP_FROM=sf-noreply@corp.local
ADMIN_EMAIL=it-admin@corp.local

# 路徑 (Linux 版本, 蓋掉 config.py 內 Windows 預設)
DATA_EXCHANGE_ROOT=/data/exchange
PORTAL_LOG_DIR=$PORTAL_DIR/logs
PORTAL_BACKUP_DIR=$PORTAL_DIR/backups

# Batch
BATCH_IDLE_SECONDS=30
BATCH_SAFETY_MINUTES=5
APPROVAL_TIMEOUT_DAYS=7

# 保留期
HOME_RETENTION_DAYS=7
SAMBA_RETENTION_DAYS=7
AUDITLOG_ONLINE_DAYS=365
AUDITLOG_ARCHIVE_YEARS=5
EOF
chmod 640 "$PORTAL_DIR/app/.env"
chown "$RUN_USER:$RUN_USER" "$PORTAL_DIR/app/.env"
ok ".env 寫入 $PORTAL_DIR/app/.env"

# 必要時建 DATA_ROOT
mkdir -p /data/exchange
chown "$RUN_USER:$RUN_USER" /data/exchange

# Portal 跑時要寫 log
chown -R "$RUN_USER:$RUN_USER" "$PORTAL_DIR"

# === Step 7: 寫 sf-portal.service ===
step "Step 7: 寫 systemd unit"

GUNICORN_BIN=""
for c in /usr/bin/gunicorn /usr/bin/gunicorn-3 /usr/local/bin/gunicorn; do
    [[ -x "$c" ]] && GUNICORN_BIN="$c" && break
done
[[ -n "$GUNICORN_BIN" ]] || GUNICORN_BIN=$(command -v gunicorn 2>/dev/null || command -v gunicorn-3 2>/dev/null || echo "")

if [[ -z "$GUNICORN_BIN" ]]; then
    fail "找不到 gunicorn binary, EPEL RPM 沒裝起來?"
fi
ok "gunicorn binary: $GUNICORN_BIN"

cat > /etc/systemd/system/sf-portal.service <<EOF
[Unit]
Description=SF File Exchange Portal (gunicorn)
After=network.target postgresql.service

[Service]
Type=simple
User=$RUN_USER
Group=$RUN_USER
WorkingDirectory=$PORTAL_DIR/app
Environment="PYTHONPATH=$PORTAL_DIR/app"
ExecStart=$GUNICORN_BIN --workers 3 --bind 127.0.0.1:5000 --access-logfile $PORTAL_DIR/logs/access.log --error-logfile $PORTAL_DIR/logs/error.log wsgi:app
Restart=on-failure
RestartSec=10

StandardOutput=append:$PORTAL_DIR/logs/portal-stdout.log
StandardError=append:$PORTAL_DIR/logs/portal-stderr.log

[Install]
WantedBy=multi-user.target
EOF
ok "sf-portal.service 寫入"

systemctl daemon-reload

# === Step 8: nginx 反代 + 防火牆 ===
step "Step 8: nginx 反代 80 → 5000 + 防火牆放行"

NGINX_CONF="/etc/nginx/conf.d/sf-portal.conf"
if [[ ! -f "$NGINX_CONF" ]]; then
    sed -i 's|listen       80 default_server;|listen       80;|' /etc/nginx/nginx.conf 2>/dev/null || true

    cat > "$NGINX_CONF" <<'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    access_log /var/log/nginx/sf-portal-access.log;
    error_log  /var/log/nginx/sf-portal-error.log;

    client_max_body_size 500M;

    location / {
        proxy_pass         http://127.0.0.1:5000;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
        proxy_read_timeout 300s;
        proxy_connect_timeout 75s;
    }
}
EOF
    ok "nginx 反代設定寫入 $NGINX_CONF"
else
    ok "nginx 反代設定已存在 $NGINX_CONF"
fi

if nginx -t 2>&1 | grep -q 'syntax is ok'; then
    systemctl reload nginx 2>&1 | tail -2 || true
    ok "nginx reload"
else
    warn "nginx config 有問題:"
    nginx -t 2>&1 | tail -3
fi

if systemctl is-active firewalld &>/dev/null; then
    firewall-cmd --permanent --add-service=http 2>&1 | tail -2 || true
    firewall-cmd --reload 2>&1 | tail -2 || true
    ok "防火牆放行 80"
fi

if command -v setsebool &>/dev/null && getenforce 2>/dev/null | grep -q Enforcing; then
    setsebool -P httpd_can_network_connect on 2>&1 | tail -2 || warn "SELinux setsebool 失敗"
    ok "SELinux: httpd_can_network_connect=on"
fi

# === Step 9: 啟動 + 驗證 ===
step "Step 9: 啟動 sf-portal + 驗證"

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

echo ""
if $PORTAL_OK; then
    MAIN_IP=$(ip -4 addr | grep -E 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}' | cut -d/ -f1)
    NGINX_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 http://localhost/ 2>/dev/null || echo 000)

    echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${GREEN}║   ✅ Portal 部署完成                                          ║${NC}"
    echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "  Portal (給 USER 用)   : http://$MAIN_IP/        (nginx 反代, HTTP $NGINX_CODE)"
    echo "  Portal (debug 直連)   : http://$MAIN_IP:5000/"
    echo "  DB 密碼               : $DB_PASS"
    echo "  .env                  : $PORTAL_DIR/app/.env"
    echo ""
    echo "  systemctl status sf-portal"
    echo "  journalctl -u sf-portal -f"
    echo "  tail -f $PORTAL_DIR/logs/error.log"
else
    echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║   ❌ Portal 沒起來, 看下方 log                                ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "=== systemctl status sf-portal ==="
    systemctl status sf-portal --no-pager -l 2>&1 | head -20
    echo ""
    echo "=== journalctl -u sf-portal 最後 30 行 ==="
    journalctl -u sf-portal -n 30 --no-pager 2>&1
    echo ""
    echo "=== $PORTAL_DIR/logs/error.log 最後 40 行 ==="
    tail -40 "$PORTAL_DIR/logs/error.log" 2>&1
    echo ""
    echo "→ 手動 debug 跑這條看完整 traceback:"
    echo "    cd $PORTAL_DIR/app"
    echo "    sudo -u $RUN_USER $GUNICORN_BIN --workers 1 --bind 127.0.0.1:5001 --log-level debug --chdir $PORTAL_DIR/app wsgi:app"
    exit 1
fi
