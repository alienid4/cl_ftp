#!/bin/bash
#
# fix_portal.sh — 從零重建 Portal (用公司 dnf mirror, 不用 pip)
#
# 對應 diagnose.sh 找到的 5 個問題:
#   - sf-portal.service 不存在
#   - Port 5000 沒監聽
#   - /opt/portal/app/wsgi.py 不存在
#   - /opt/portal/venv 不存在
#   - firewall 沒放行 80/5000
#
# 用法:
#   curl -fsSL https://github.com/alienid4/cl_ftp/raw/main/deploy-rhel/fix_portal.sh | sudo bash
#

set -euo pipefail

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
echo -e "${BOLD}${CYAN}║   fix_portal.sh — 重建 SF Portal service                     ║${NC}"
echo -e "${BOLD}${CYAN}║   (純 RHEL BaseOS/AppStream, 不用 EPEL, 不用 pip / venv)     ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"

# === Step 1: 裝 Python 套件 ===
# 策略:
#   1a. 先 dnf 裝 RHEL BaseOS/AppStream 有的 (python3, pip, psycopg2, cryptography, requests)
#   1b. EPEL 套件 (flask, werkzeug, gunicorn, ldap...) 從 git 拉預打好的 tar 安裝
#       對應 GitHub Actions: .github/workflows/build-epel-pyrpms.yml
step "Step 1a: 裝 RHEL BaseOS/AppStream Python 套件"

dnf install -y \
    python3 python3-pip \
    python3-psycopg2 \
    python3-cryptography python3-requests 2>&1 | tail -5

# 確認 RHEL 套件可 import
for mod in psycopg2 cryptography; do
    if /usr/bin/python3 -c "import $mod" 2>/dev/null; then
        ok "python3 -c 'import $mod' OK (來自 RHEL repo)"
    else
        fail "$mod import 失敗 — 確認 AppStream repo enabled"
    fi
done

# === Step 1b: EPEL Python RPM tar 安裝 (公司禁 EPEL + SF 不能上網的解法) ===
step "Step 1b: 找 EPEL Python RPM tar"

EPEL_DIR="/tmp/sf-epel-pyrpms"
mkdir -p "$EPEL_DIR"
cd "$EPEL_DIR"

# 優先順序: 本地檔 → curl github
# (SF 主機不能上網的話, USER 要先在 PC 抓 tar 拷到下列任一位置)
EPEL_TAR_CANDIDATES=(
    "/opt/sf/release-zip/sf-epel-pyrpms.tar.gz"   # git clone 過就有
    "/opt/sf/sf-epel-pyrpms.tar.gz"
    "/tmp/sf-epel-pyrpms.tar.gz"
    "/root/sf-epel-pyrpms.tar.gz"
)

EPEL_TAR_FOUND=""
for p in "${EPEL_TAR_CANDIDATES[@]}"; do
    if [[ -f "$p" ]]; then
        EPEL_TAR_FOUND="$p"
        cp "$p" "$EPEL_DIR/sf-epel-pyrpms.tar.gz"
        ok "找到本地 tar: $p"
        break
    fi
done

# 沒找到本地, 試 curl github (SF 有外網才會成功)
if [[ -z "$EPEL_TAR_FOUND" ]]; then
    EPEL_TAR_URL="https://github.com/alienid4/cl_ftp/raw/main/release-zip/sf-epel-pyrpms.tar.gz"
    warn "本地沒找到 tar, 嘗試 curl github (10 秒 timeout)..."
    if curl -fsSL --max-time 10 -o sf-epel-pyrpms.tar.gz "$EPEL_TAR_URL"; then
        ok "github curl 成功"
        EPEL_TAR_FOUND="$EPEL_TAR_URL"
    else
        echo ""
        fail "
EPEL tar 找不到. 請按以下步驟:

  1. 在能連 github 的 PC 下載:
     https://github.com/alienid4/cl_ftp/raw/main/release-zip/sf-epel-pyrpms.tar.gz

  2. 透過你公司核可的方式拷到 SF 主機, 放任一位置:
     - /opt/sf/release-zip/sf-epel-pyrpms.tar.gz   (建議, 跟 git repo 一致)
     - /opt/sf/sf-epel-pyrpms.tar.gz
     - /tmp/sf-epel-pyrpms.tar.gz
     - /root/sf-epel-pyrpms.tar.gz

  3. 或如果 /opt/sf 是 git clone 的:
     cd /opt/sf && git pull
     (tar 會跟著 git pull 一起到位)

  4. 重跑本腳本.
"
    fi
fi

tar xzf sf-epel-pyrpms.tar.gz
RPM_COUNT=$(ls rpms/*.rpm 2>/dev/null | wc -l)
if [[ "$RPM_COUNT" -lt 5 ]]; then
    fail "解壓後 RPM 太少 ($RPM_COUNT), tar 損壞"
fi
ok "解壓 $RPM_COUNT 個 EPEL RPM"

# dnf install local RPMs (--disablerepo=* 避免去找線上 EPEL)
echo "[exec] dnf install local RPMs ..."
dnf install -y --disablerepo='*' --nogpgcheck ./rpms/*.rpm 2>&1 | tail -10 || {
    warn "dnf install 部分失敗, 嘗試 rpm -Uvh ..."
    rpm -Uvh --replacefiles --replacepkgs ./rpms/*.rpm 2>&1 | tail -10 || \
        fail "EPEL RPM 安裝失敗"
}

# 確認 EPEL 來的模組可 import
MISSING=()
for mod in flask werkzeug; do
    if /usr/bin/python3 -c "import $mod" 2>/dev/null; then
        ok "python3 -c 'import $mod' OK (來自 EPEL tar)"
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

if [[ -d /opt/sf/portal ]]; then
    cp -r /opt/sf/portal/* /opt/portal/app/
    ok "拷貝 /opt/sf/portal/* -> /opt/portal/app/"
else
    fail "/opt/sf/portal 不存在, 請先跑 install_online.sh 拉 repo"
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

if [[ ! -f /opt/portal/app/appsettings.json ]]; then
    # 從 PostgreSQL 取或建 portal user
    sudo -u postgres psql <<EOF 2>&1 | tail -5
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_database WHERE datname = 'file_exchange_audit') THEN
        CREATE DATABASE file_exchange_audit;
    END IF;
END \$\$;

DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_user WHERE usename = 'portal') THEN
        CREATE USER portal WITH PASSWORD '$DB_PASS';
    ELSE
        ALTER USER portal WITH PASSWORD '$DB_PASS';
    END IF;
END \$\$;

GRANT ALL PRIVILEGES ON DATABASE file_exchange_audit TO portal;
EOF

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

    # 套 schema 如果有
    if [[ -f /opt/sf/sql/01_create_db_postgres.sql ]]; then
        sudo -u postgres psql -d file_exchange_audit < /opt/sf/sql/01_create_db_postgres.sql 2>&1 | tail -3 || warn "schema 套用部分失敗"
        ok "Schema 套用"
    fi
else
    ok "appsettings.json 已存在, skip"
fi

# 修 pg_hba.conf 允許 portal 連
PG_HBA=$(find /var/lib/pgsql /etc/postgresql -name pg_hba.conf 2>/dev/null | head -1)
if [[ -n "$PG_HBA" ]] && ! grep -q "host.*file_exchange_audit.*portal.*127.0.0.1" "$PG_HBA"; then
    echo "host    file_exchange_audit    portal    127.0.0.1/32    md5" >> "$PG_HBA"
    systemctl reload postgresql
    ok "pg_hba.conf 允許 portal 連 (127.0.0.1)"
fi

# === Step 4: 寫 systemd unit ===
step "Step 4: 寫 systemd unit /etc/systemd/system/sf-portal.service"

# 判斷: 有 gunicorn 用 gunicorn (production), 沒有就用 Flask 內建
if command -v gunicorn-3 &>/dev/null || /usr/bin/python3 -c "import gunicorn" 2>/dev/null; then
    EXEC_LINE='ExecStart=/usr/bin/gunicorn-3 --workers 3 --bind 127.0.0.1:5000 --access-logfile /opt/portal/logs/access.log --error-logfile /opt/portal/logs/error.log wsgi:app'
    SERVER_DESC="gunicorn"
else
    EXEC_LINE='ExecStart=/usr/bin/python3 -m flask run --host=127.0.0.1 --port=5000 --no-debugger --no-reload'
    SERVER_DESC="Flask built-in werkzeug"
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
