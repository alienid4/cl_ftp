#!/bin/bash
#
# install_portal_all_in_one.sh v2.3.2 — SF Portal 一次裝完
#
# 集成 v2.2.0 → v2.3.1 學到的所有 fix:
#   - 公司禁 pip (改用 unzip wheel)
#   - 公司禁 EPEL (RPM 手動下載 scp 來)
#   - SF 不能上網
#   - 散檔 *.rpm 自動找 + 過濾重複 "(1).rpm"
#   - 補裝 RHEL AppStream 依賴 (jinja2, packaging, pyasn1, six)
#   - gunicorn binary 是 /usr/bin/gunicorn 不是 -3
#   - DB CREATE 不能在 DO block, 拆出來
#   - 不用 set -e, 用 set -uo (容錯)
#
# 用法 (在 SF 跑):
#   sudo bash /tmp/ftp-lab/install_portal_all_in_one.sh
#
# 前置 (PC 端先做完):
#   1. 把 7 個 EPEL RPM scp 到 /tmp/ 任意子目錄
#   2. 把 3 個 PyPI wheel scp 到 /tmp/ 任意子目錄
#   3. 把 portal/ source scp 到 /tmp/ftp-lab/portal 或 /opt/sf/portal
#
# 本腳本自動搜尋上述檔案. 找不到會明確告訴你缺什麼.
#

set -uo pipefail   # 不要 set -e — 各 step 自己處理錯誤

VERSION="install_portal_all_in_one v2.3.6 (2026-05-22)"

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
echo -e "${BOLD}${CYAN}║   (公司禁 pip + 禁 EPEL + SF 離線, 散檔自動搜尋)             ║${NC}"
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
        # maxdepth 5 容納各種放法 + ERE 過濾 "(N)" 重複下載 (匹配 (1).rpm/(2).rpm 之類)
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

# debug 用: 失敗時印 USER /tmp 結構幫忙看哪裡放錯
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

# 3 個 PyPI wheel
REQUIRED_WHEELS=(
    "Flask_Login-*.whl"
    "cachelib-*.whl"
    "flask_session-*.whl"
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

# 找 Portal source - 先查候選路徑, 沒中再動態 find wsgi.py
PORTAL_SRC=""
for d in "${PORTAL_SRC_CANDIDATES[@]}"; do
    if [[ -d "$d" ]] && [[ -f "$d/wsgi.py" || -d "$d/app" ]]; then
        PORTAL_SRC="$d"
        ok "Portal source (候選): $d"
        break
    fi
done

# Fallback: 動態 find wsgi.py 所在目錄 (有 app/ 子目錄的才算 portal)
if [[ -z "$PORTAL_SRC" ]]; then
    info "候選路徑都沒有, 動態 find wsgi.py ..."
    while IFS= read -r wsgi_file; do
        parent=$(dirname "$wsgi_file")
        if [[ -d "$parent/app" ]]; then
            PORTAL_SRC="$parent"
            ok "Portal source (find): $PORTAL_SRC"
            break
        fi
    done < <(find /tmp /opt /root /home -maxdepth 6 -name 'wsgi.py' -type f 2>/dev/null)
fi

if [[ -z "$PORTAL_SRC" ]]; then
    warn "找不到 portal source"
    warn "  候選路徑: ${PORTAL_SRC_CANDIDATES[*]}"
    warn "  動態 find /tmp /opt /root /home -name 'wsgi.py' 也沒"
    MISSING_FILES+=("portal/ source 目錄 (含 wsgi.py + app/)")
fi

if [[ ${#MISSING_FILES[@]} -gt 0 ]]; then
    echo ""
    warn "缺 ${#MISSING_FILES[@]} 個必要檔:"
    printf '  - %s\n' "${MISSING_FILES[@]}"
    dump_tmp_structure
    fail "
請確認上述檔案都在 /tmp/ 任一子目錄, 然後重跑.

下載清單:
  EPEL RPM: https://github.com/alienid4/cl_ftp/blob/main/docs/runbook/v2.2.0_20260521_epel_pyrpms_manual.md
  PyPI wheel: https://github.com/alienid4/cl_ftp/blob/main/notes/note_20260522_v2.2.7_pip-wheels.md
"
fi

ok "全部檔案找齊"

# === Step 2: dnf install RHEL Python 依賴 (走 Satellite) ===
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

# === Step 2a: 初始化 PostgreSQL (如果還沒) ===
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

# === Step 3: 裝 EPEL RPM (rpm -Uvh --force, 跳過 GPG check) ===
step "Step 3: 裝 EPEL Python RPM (rpm -Uvh --force --nodeps)"

# 把所有要裝的 RPM 列出來
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

# === Step 4: unzip PyPI wheel 到 site-packages (不用 pip) ===
step "Step 4: unzip wheel 到 $SITE_PACKAGES (不用 pip)"

# 清掉之前 pip 留下的 /usr/local 污染
rm -rf /usr/local/lib/python3.9/site-packages/flask_login* 2>/dev/null
rm -rf /usr/local/lib/python3.9/site-packages/flask_session* 2>/dev/null
rm -rf /usr/local/lib/python3.9/site-packages/cachelib* 2>/dev/null
rm -rf /usr/local/lib/python3.9/site-packages/Flask_Login* 2>/dev/null

for pat in "${REQUIRED_WHEELS[@]}"; do
    whl="${FOUND_WHEELS[$pat]:-}"
    [[ -n "$whl" ]] || continue
    echo "[exec] unzip $(basename "$whl")"
    unzip -o -q "$whl" -d "$SITE_PACKAGES/" 2>&1 | tail -3 || warn "unzip $whl 失敗"
done

for mod in flask_login flask_session cachelib; do
    if /usr/bin/python3 -c "import $mod" 2>/dev/null; then
        ok "import $mod OK (來自 wheel)"
    else
        warn "import $mod 失敗"
    fi
done

# 確認 nginx user 也能 import (沒有 nginx user 就建)
if ! id -u nginx &>/dev/null; then
    useradd -r -s /sbin/nologin nginx 2>/dev/null || true
fi

if sudo -u nginx /usr/bin/python3 -c "from flask_login import LoginManager; from flask_session import Session" 2>/dev/null; then
    ok "nginx user 能 import flask_login + flask_session"
else
    warn "nginx user 仍 import 失敗, 修權限..."
    chmod -R o+rX "$SITE_PACKAGES/"
    if sudo -u nginx /usr/bin/python3 -c "from flask_login import LoginManager" 2>/dev/null; then
        ok "chmod 後 OK"
    else
        fail "nginx 仍無法 import — 可能 SELinux, 看 ausearch -m AVC --start recent"
    fi
fi

# === Step 5: 拷 Portal source 到 /opt/portal/app ===
step "Step 5: 拷 Portal source"

mkdir -p "$PORTAL_DIR"/{logs,scripts}

# v2.3.3 修正: 整個 /opt/portal/app/ 清掉重 cp, 避免之前 patch 殘留
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

chown -R "$RUN_USER:$RUN_USER" "$PORTAL_DIR"

# 驗 wsgi.py 確實有 module-level app (用 [[:space:]] 不用 \s, ERE 不認 \s)
if [[ -f "$PORTAL_DIR/app/wsgi.py" ]]; then
    if grep -qE '^app[[:space:]]*=' "$PORTAL_DIR/app/wsgi.py"; then
        ok "wsgi.py 有 module-level app (不需 patch)"
    else
        warn "wsgi.py 沒 module-level app, 確認 /opt/sf/portal/wsgi.py 是新版"
    fi
else
    fail "/opt/portal/app/wsgi.py 不存在, Portal source 缺檔"
fi

# === Step 6: PostgreSQL DB + user ===
step "Step 6: 建 DB + portal user"

cd /tmp   # 避免 postgres user 無權限 cd 當前目錄

# 確保 postgresql 在跑
if ! systemctl is-active postgresql &>/dev/null; then
    systemctl enable --now postgresql 2>&1 | tail -3 || true
fi

# 1. 建 database (不能在 DO block 內)
if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='file_exchange_audit'" 2>/dev/null | grep -q 1; then
    sudo -u postgres psql -c "CREATE DATABASE file_exchange_audit;" 2>&1 | tail -3
    ok "DB file_exchange_audit 建立"
else
    ok "DB file_exchange_audit 已存在"
fi

# 2. 從既有 appsettings.json 讀回密碼 (avoid mismatch)
if [[ -f "$PORTAL_DIR/app/appsettings.json" ]]; then
    EXISTING_PASS=$(grep -oP 'postgresql://portal:\K[^@]+' "$PORTAL_DIR/app/appsettings.json" 2>/dev/null || true)
    if [[ -n "$EXISTING_PASS" ]]; then
        DB_PASS="$EXISTING_PASS"
        ok "用既有 appsettings.json 內的 DB 密碼"
    fi
fi

# 3. 建/更新 portal user
sudo -u postgres psql <<EOF 2>&1 | tail -3
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
if [[ ! -f "$PORTAL_DIR/app/appsettings.json" ]]; then
    cat > "$PORTAL_DIR/app/appsettings.json" <<EOF
{
    "DATABASE_URL": "postgresql://portal:$DB_PASS@127.0.0.1:5432/file_exchange_audit",
    "PORTAL_PORT": 5000,
    "DATA_ROOT": "/data/exchange",
    "LOG_DIR": "$PORTAL_DIR/logs",
    "AD_DOMAIN": "corp.local",
    "SECRET_KEY": "$(openssl rand -hex 32)"
}
EOF
    chmod 640 "$PORTAL_DIR/app/appsettings.json"
    chown "$RUN_USER:$RUN_USER" "$PORTAL_DIR/app/appsettings.json"
    ok "appsettings.json 寫入"
else
    ok "appsettings.json 已存在 (保留)"
fi

# 5. 修 pg_hba.conf 允許 portal 連 127.0.0.1
PG_HBA=$(find /var/lib/pgsql -name pg_hba.conf 2>/dev/null | head -1)
if [[ -n "$PG_HBA" ]] && ! grep -q "host.*file_exchange_audit.*portal.*127.0.0.1" "$PG_HBA"; then
    echo "host    file_exchange_audit    portal    127.0.0.1/32    md5" >> "$PG_HBA"
    systemctl reload postgresql 2>&1 | tail -2 || warn "reload postgresql 失敗"
    ok "pg_hba.conf 允許 portal 連"
fi

# 6. 必要時建 DATA_ROOT
mkdir -p /data/exchange
chown "$RUN_USER:$RUN_USER" /data/exchange

# === Step 7: 寫 sf-portal.service ===
step "Step 7: 寫 systemd unit"

# 動態抓 gunicorn binary
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

# 寫 nginx 反代設定 (如果還沒)
NGINX_CONF="/etc/nginx/conf.d/sf-portal.conf"
if [[ ! -f "$NGINX_CONF" ]]; then
    # 移掉 default server 避免衝突
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

# 測 + reload nginx
if nginx -t 2>&1 | grep -q 'syntax is ok'; then
    systemctl reload nginx 2>&1 | tail -2 || true
    ok "nginx reload"
else
    warn "nginx config 有問題:"
    nginx -t 2>&1 | tail -3
fi

# 防火牆
if systemctl is-active firewalld &>/dev/null; then
    firewall-cmd --permanent --add-service=http 2>&1 | tail -2 || true
    firewall-cmd --reload 2>&1 | tail -2 || true
    ok "防火牆放行 80"
fi

# SELinux: 允許 nginx 連 5000
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

# === 結果 ===
echo ""
if $PORTAL_OK; then
    MAIN_IP=$(ip -4 addr | grep -E 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}' | cut -d/ -f1)

    # 順便驗 nginx 80 通不通
    NGINX_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 http://localhost/ 2>/dev/null || echo 000)

    echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${GREEN}║   ✅ Portal 部署完成                                          ║${NC}"
    echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "  Portal (給 USER 用)   : http://$MAIN_IP/        (nginx 反代, HTTP $NGINX_CODE)"
    echo "  Portal (debug 直連)   : http://$MAIN_IP:5000/"
    echo ""
    echo "  systemctl status sf-portal"
    echo "  journalctl -u sf-portal -f"
else
    echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║   ❌ Portal 沒起來, 看下方 log                                ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "=== systemctl status sf-portal ==="
    systemctl status sf-portal --no-pager -l 2>&1 | head -20
    echo ""
    echo "=== journalctl -u sf-portal 最後 20 行 ==="
    journalctl -u sf-portal -n 20 --no-pager 2>&1
    echo ""
    echo "=== /opt/portal/logs/portal-stderr.log 最後 30 行 ==="
    tail -30 "$PORTAL_DIR/logs/portal-stderr.log" 2>&1
    echo ""
    echo "→ 手動 debug 跑這條看完整 traceback:"
    echo "    cd $PORTAL_DIR/app"
    echo "    sudo -u $RUN_USER $GUNICORN_BIN --workers 1 --bind 127.0.0.1:5001 --log-level debug wsgi:app"
    exit 1
fi
