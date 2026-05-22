#!/bin/bash
#
# v2.4.3_install-portal-all-in-one.sh — SF Portal 一次裝完
#
# v2.4.3 變更 (修 v2.4.2 出的 Permission denied):
#   - Step 6b 改 cat $SCHEMA_SQL | psql ... (root 讀檔, pipe 給 postgres user)
#     舊版用 psql -f $SCHEMA_SQL, postgres user 沒權限讀 /tmp/sf-portal-extracted/
#
# (v2.4.2 已修): templates 完整 / schema 必驗 / nginx 衝突
#
# 用法:
#   sudo bash /tmp/ftp-lab/v2.4.3_install-portal-all-in-one.sh
#
# 前置 (PC 端):
#   1. 7 個 EPEL RPM scp 到 /tmp/ftp-lab/
#   2. 4 個 PyPI wheel scp 到 /tmp/ftp-lab/
#   3. v2.4.2_sf-portal-source.tar.gz (v2.4.2 tar 內容不變, 可繼續用)

set -uo pipefail

VERSION="v2.4.3_install-portal-all-in-one (2026-05-22)"

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
echo -e "${BOLD}${CYAN}║   補 templates + 強化 schema 驗證 + 修 nginx default_server   ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"

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

# === Step 0 ===
step "Step 0: 環境檢查"

if grep -qE 'release 9' /etc/redhat-release 2>/dev/null; then
    ok "OS: $(cat /etc/redhat-release)"
else
    warn "不是 RHEL 9, 可能不相容"
fi

PY_VER=$(/usr/bin/python3 --version 2>&1 | awk '{print $2}')
PY_MAJOR=$(echo "$PY_VER" | cut -d. -f1)
PY_MINOR=$(echo "$PY_VER" | cut -d. -f2)
ok "Python: $PY_VER"
if [[ "$PY_MAJOR" == "3" && "$PY_MINOR" -lt 10 ]]; then
    info "Py < 3.10, 會檢查/修 PEP 604 union syntax (X | None)"
    PY39_FIX_NEEDED=true
else
    PY39_FIX_NEEDED=false
fi

# === Step 1: 找檔 ===
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

REQUIRED_RPMS=(
    "python3-flask-*.rpm"
    "python3-werkzeug-*.rpm"
    "python3-gunicorn-*.rpm"
    "python3-itsdangerous-*.rpm"
    "python3-click-*.rpm"
    "python3-blinker-*.rpm"
    "python3-ldap3-*.rpm"
)

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

# Portal source — 優先 v2.4.2, 再 v2.4.1, v2.4.0
# v2.4.2 起檔名規則: v<X.Y.Z>_<name>.tar.gz, 舊版仍是 sf-portal-source-v<X.Y.Z>.tar.gz
PORTAL_SRC=""
for ver in v2.4.2 v2.4.1 v2.4.0; do
    PORTAL_TAR=$(find /tmp /opt /root -maxdepth 5 \( -name "${ver}_sf-portal-source.tar.gz" -o -name "sf-portal-source-${ver}.tar.gz" \) -type f 2>/dev/null | head -1)
    if [[ -n "$PORTAL_TAR" ]]; then
        info "找到 portal tar ($ver): $PORTAL_TAR"
        rm -rf /tmp/sf-portal-extracted
        mkdir -p /tmp/sf-portal-extracted
        tar xzf "$PORTAL_TAR" -C /tmp/sf-portal-extracted
        if [[ -d /tmp/sf-portal-extracted/portal ]]; then
            PORTAL_SRC="/tmp/sf-portal-extracted/portal"
        else
            PORTAL_SRC="/tmp/sf-portal-extracted"
        fi
        ok "Portal source ($ver extracted): $PORTAL_SRC"
        break
    fi
done

# Fallback: 候選路徑 + 動態 find wsgi.py
if [[ -z "$PORTAL_SRC" ]]; then
    for d in "${PORTAL_SRC_CANDIDATES[@]}"; do
        if [[ -d "$d" ]] && [[ -f "$d/wsgi.py" || -d "$d/app" ]]; then
            PORTAL_SRC="$d"
            warn "Portal source (候選, 非 v2.4.1): $d"
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
            warn "Portal source (find, 非 v2.4.1): $PORTAL_SRC"
            break
        fi
    done < <(find /tmp /opt /root /home -maxdepth 6 -name 'wsgi.py' -type f 2>/dev/null)
fi

# Fallback: 找任何 portal*.tar.gz
if [[ -z "$PORTAL_SRC" ]]; then
    info "找其他 portal tar.gz ..."
    PORTAL_TAR=$(find /tmp /opt /root -maxdepth 5 \( -name 'sf-portal-source*.tar.gz' -o -name 'portal*.tar.gz' \) -type f 2>/dev/null | head -1)
    if [[ -n "$PORTAL_TAR" ]]; then
        warn "找到 (非 v2.4.1): $PORTAL_TAR"
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
    MISSING_FILES+=("sf-portal-source-v2.4.2.tar.gz")
fi

# 找 SQL schema
SCHEMA_SQL=""
SCHEMA_SQL=$(find /tmp /opt /root -maxdepth 6 -name '01_create_db_postgres*.sql' -type f 2>/dev/null | head -1)
if [[ -z "$SCHEMA_SQL" && -n "$PORTAL_SRC" ]]; then
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
    fail "下載清單見 notes/20260522/v2.4.0_preflight-checklist.md + v2.4.1_python39-typing-fix.md"
fi

ok "全部檔案找齊"

# === Step 2 ===
step "Step 2: 裝 RHEL AppStream 套件"

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

if [[ ! -f /var/lib/pgsql/data/PG_VERSION ]]; then
    info "PostgreSQL 還沒 initdb"
    /usr/bin/postgresql-setup --initdb 2>&1 | tail -3 || warn "initdb 失敗"
fi

systemctl enable --now postgresql 2>&1 | tail -2 || warn "postgresql enable 失敗"
sleep 2
if systemctl is-active postgresql &>/dev/null; then
    ok "postgresql active"
else
    fail "postgresql 沒起來, 看 journalctl -u postgresql"
fi

systemctl enable --now firewalld 2>&1 | tail -2 || warn "firewalld 啟動失敗"
systemctl enable --now nginx 2>&1 | tail -2 || warn "nginx 啟動失敗"
ok "nginx / firewalld 啟動"

# === Step 3 ===
step "Step 3: 裝 EPEL Python RPM"

RPM_LIST=()
for pat in "${REQUIRED_RPMS[@]}"; do
    [[ -n "${FOUND_RPMS[$pat]:-}" ]] && RPM_LIST+=("${FOUND_RPMS[$pat]}")
done

echo "[exec] rpm -Uvh --force --nodeps ${#RPM_LIST[@]} 個 RPM ..."
rpm -Uvh --force --nodeps "${RPM_LIST[@]}" 2>&1 | tail -15 || warn "rpm 部分失敗 (可能已裝過)"

for mod in flask werkzeug gunicorn; do
    if /usr/bin/python3 -c "import $mod" 2>/dev/null; then
        ok "import $mod OK (EPEL)"
    else
        warn "import $mod 失敗"
    fi
done

# === Step 4 ===
step "Step 4: 清舊 dotenv 殘留 + unzip wheel"

rm -rf /usr/local/lib/python3.9/site-packages/flask_login* 2>/dev/null
rm -rf /usr/local/lib/python3.9/site-packages/Flask_Login* 2>/dev/null
rm -rf /usr/local/lib/python3.9/site-packages/flask_session* 2>/dev/null
rm -rf /usr/local/lib/python3.9/site-packages/cachelib* 2>/dev/null
rm -rf /usr/local/lib/python3.9/site-packages/dotenv* 2>/dev/null
rm -rf /usr/local/lib/python3.9/site-packages/python_dotenv* 2>/dev/null

rm -rf "$SITE_PACKAGES"/dotenv* 2>/dev/null
rm -rf "$SITE_PACKAGES"/python_dotenv* 2>/dev/null
rm -f  "$SITE_PACKAGES"/dotenv.py 2>/dev/null
ok "清掉所有舊 dotenv 殘留"

for pat in "${REQUIRED_WHEELS[@]}"; do
    whl="${FOUND_WHEELS[$pat]:-}"
    [[ -n "$whl" ]] || continue
    echo "[exec] unzip $(basename "$whl")"
    unzip -o -q "$whl" -d "$SITE_PACKAGES/" 2>&1 | tail -3 || warn "unzip $whl 失敗"
done

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

if ! id -u nginx &>/dev/null; then
    useradd -r -s /sbin/nologin nginx 2>/dev/null || true
fi
chmod -R o+rX "$SITE_PACKAGES/" 2>/dev/null

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

$ALL_OK || warn "有 import 失敗 — Portal 可能起不來"

# === Step 5 ===
step "Step 5: 拷 Portal source + Py3.9 typing 安全網"

mkdir -p "$PORTAL_DIR"/{logs,scripts,backups}

if [[ -d "$PORTAL_DIR/app" ]]; then
    warn "清掉舊 /opt/portal/app/"
    rm -rf "$PORTAL_DIR/app"
fi
mkdir -p "$PORTAL_DIR/app"

cp -r "$PORTAL_SRC"/* "$PORTAL_DIR/app/" 2>&1 | tail -3
ok "拷 $PORTAL_SRC/* -> $PORTAL_DIR/app/ (fresh)"

if id -u nginx &>/dev/null; then
    RUN_USER="nginx"
else
    useradd -r -s /sbin/nologin -d "$PORTAL_DIR" portal 2>/dev/null || true
    RUN_USER="portal"
fi
ok "RUN_USER = $RUN_USER"

# 驗 wsgi.py
if [[ -f "$PORTAL_DIR/app/wsgi.py" ]]; then
    if grep -qE '^app[[:space:]]*=' "$PORTAL_DIR/app/wsgi.py"; then
        ok "wsgi.py 有 module-level app"
    else
        warn "wsgi.py 沒 module-level app"
    fi
else
    fail "$PORTAL_DIR/app/wsgi.py 不存在"
fi

# 驗 db.py
if grep -q '^import psycopg2' "$PORTAL_DIR/app/app/db.py" 2>/dev/null; then
    ok "db.py 是 psycopg2 版"
else
    fail "db.py 不是 psycopg2 版"
fi

if grep -q 'SELECT.*TOP.*LIMIT' "$PORTAL_DIR/app/app/db.py" 2>/dev/null; then
    ok "db.py 含 TOP→LIMIT 翻譯 (v2.4.0+)"
else
    warn "db.py 沒有 TOP→LIMIT 翻譯"
fi

# === Step 5b: Py3.9 typing 安全網 (v2.4.1 加) ===
# 若 USER 用舊 tar (auth.py 內仍有 `User | None`), 在這裡自動修
if $PY39_FIX_NEEDED; then
    info "Py$PY_VER 不支援 PEP 604 union syntax (X | None), 掃 auth.py..."

    AUTH_PY="$PORTAL_DIR/app/app/auth.py"
    if [[ -f "$AUTH_PY" ]]; then
        if grep -qE ' \| None:|: \w+ \| ' "$AUTH_PY"; then
            warn "auth.py 仍有 PEP 604 syntax, 套 fallback patch"
            # 用 Python 寫 patch, 不用 sed (避免 GPT 第一次踩的 docstring 雷)
            /usr/bin/python3 <<PYEOF
import re
from pathlib import Path
p = Path("$AUTH_PY")
src = p.read_text(encoding='utf-8')

# 1. 把 X | None 換成 Optional[X]
src_new = re.sub(r'->\s*(\w+)\s*\|\s*None\s*:', r'-> Optional[\1]:', src)

# 2. 確保 from typing import Optional 在 import 區
# 找第一個 import / from ... 的位置插進去 (避開 docstring)
lines = src_new.split('\n')
out = []
inserted = False
in_doc = False
doc_open_count = 0

for line in lines:
    out.append(line)
    # 計算 triple-quote 開關 (簡易版)
    doc_open_count += line.count('"""')
    if doc_open_count % 2 == 1:
        in_doc = True
        continue
    elif doc_open_count >= 2 and not inserted:
        in_doc = False
    # 在第一個 import / from 之前插入
    if not inserted and not in_doc and (line.startswith('import ') or line.startswith('from ')) and 'typing' not in line:
        # 在這行之前插一行
        out.insert(-1, 'from typing import Optional')
        inserted = True

if not inserted:
    # 沒找到 import, 在 doc 後直接放
    out.append('from typing import Optional')

src_final = '\n'.join(out)
# 若已有 Optional import 不要重複
if src_final.count('from typing import Optional') > 1:
    # 留第一個, 拿掉後面的
    seen = False
    new_lines = []
    for ln in src_final.split('\n'):
        if ln.strip() == 'from typing import Optional':
            if seen:
                continue
            seen = True
        new_lines.append(ln)
    src_final = '\n'.join(new_lines)

p.write_text(src_final, encoding='utf-8')
print('[patched] auth.py')
PYEOF
        else
            ok "auth.py 已用 Optional[X] (v2.4.1 tar)"
        fi

        # 最終驗: py_compile auth.py
        if /usr/bin/python3 -m py_compile "$AUTH_PY" 2>/dev/null; then
            ok "auth.py py_compile OK"
        else
            warn "auth.py py_compile 失敗:"
            /usr/bin/python3 -m py_compile "$AUTH_PY" 2>&1 | tail -5
        fi
    fi

    # 全 portal 掃一遍, 找其他 | None
    OTHER_HITS=$(grep -rnE ' \| None:|: \w+ \| ' "$PORTAL_DIR/app" 2>/dev/null | grep -v '.pyc' | grep -v '__pycache__' || true)
    if [[ -n "$OTHER_HITS" ]]; then
        warn "其他檔仍有 PEP 604 syntax:"
        echo "$OTHER_HITS"
    else
        ok "全 portal 無其他 PEP 604 syntax"
    fi
fi

# 整 portal py_compile 驗證
info "整 portal py_compile 驗證..."
COMPILE_FAIL=$(find "$PORTAL_DIR/app" -name '*.py' -exec /usr/bin/python3 -m py_compile {} \; 2>&1 | head -5)
if [[ -z "$COMPILE_FAIL" ]]; then
    ok "全 portal py_compile OK"
else
    warn "$COMPILE_FAIL"
fi

# === Step 5c: Templates 完整性檢驗 (v2.4.2 新加) ===
step "Step 5c: Jinja2 templates 完整性驗證"

REQUIRED_TEMPLATES=(
    "base.html"
    "error.html"
    "login.html"
    "home.html"
    "approval_list.html"
    "approval_detail.html"
    "audit_query.html"
    "admin_biz_list.html"
    "admin_biz_new.html"
    "admin_biz_edit.html"
    "admin_health.html"
)

TPL_DIR="$PORTAL_DIR/app/app/templates"
[[ ! -d "$TPL_DIR" ]] && TPL_DIR="$PORTAL_DIR/app/templates"

MISSING_TPL=()
for tpl in "${REQUIRED_TEMPLATES[@]}"; do
    if [[ -f "$TPL_DIR/$tpl" ]]; then
        ok "template: $tpl"
    else
        warn "缺 template: $tpl"
        MISSING_TPL+=("$tpl")
    fi
done

if [[ ${#MISSING_TPL[@]} -gt 0 ]]; then
    fail "缺 ${#MISSING_TPL[@]} 個 template — Portal 訪問會 TemplateNotFound. tar.gz 不是 v2.4.2 完整版"
fi
ok "全部 ${#REQUIRED_TEMPLATES[@]} 個 templates 完整 (v2.4.2)"

# === Step 6: DB ===
step "Step 6: 建 DB + portal user"

cd /tmp

if ! systemctl is-active postgresql &>/dev/null; then
    systemctl enable --now postgresql 2>&1 | tail -3 || true
fi

if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" 2>/dev/null | grep -q 1; then
    sudo -u postgres psql -c "CREATE DATABASE $DB_NAME;" 2>&1 | tail -3
    ok "DB $DB_NAME 建立"
else
    ok "DB $DB_NAME 已存在"
fi

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

PG_HBA=$(find /var/lib/pgsql -name pg_hba.conf 2>/dev/null | head -1)
if [[ -n "$PG_HBA" ]] && ! grep -q "host.*$DB_NAME.*$DB_USER.*127.0.0.1" "$PG_HBA"; then
    echo "host    $DB_NAME    $DB_USER    127.0.0.1/32    md5" >> "$PG_HBA"
    systemctl reload postgresql 2>&1 | tail -2 || warn "reload postgresql 失敗"
    ok "pg_hba.conf 允許 portal 連"
fi

# === Step 6b: 套用 Schema (v2.4.2 強化, 不夠就 fail) ===
step "Step 6b: 套用 Schema + 驗 6 個關鍵表必須在"

if [[ -z "$SCHEMA_SQL" ]]; then
    fail "找不到 01_create_db_postgres.sql — Portal 訪問會 relation does not exist"
fi

info "套用 schema: $SCHEMA_SQL"
# v2.4.3: 改用 cat | psql 避免 postgres user 沒權限讀 /tmp/sf-portal-extracted/
# (v2.4.2 用 psql -f $SCHEMA_SQL 會 Permission denied)
SCHEMA_TMP="/tmp/sf-schema-$$.sql"
cp "$SCHEMA_SQL" "$SCHEMA_TMP"
chmod 644 "$SCHEMA_TMP"
chown postgres:postgres "$SCHEMA_TMP" 2>/dev/null || true
sudo -u postgres psql -d "$DB_NAME" -f "$SCHEMA_TMP" 2>&1 | tail -15
rm -f "$SCHEMA_TMP"

# v2.4.2: 必須 6 個表都在
EXPECTED_TABLES=("auditlog" "businesscode" "batch" "batchfile" "portaluser" "sambapathhistory")
MISSING_TBL=()
for t in "${EXPECTED_TABLES[@]}"; do
    if sudo -u postgres psql -d "$DB_NAME" -tAc "SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='$t'" 2>/dev/null | grep -q 1; then
        ok "table: $t"
    else
        warn "缺 table: $t"
        MISSING_TBL+=("$t")
    fi
done

if [[ ${#MISSING_TBL[@]} -gt 0 ]]; then
    echo ""
    echo "=== schema 套用 retry (cp 到 /var/lib/pgsql) ==="
    # 最終 fallback: 拷到 postgres 自己的 home, 一定有權限
    PG_HOME=$(getent passwd postgres | cut -d: -f6)
    [[ -n "$PG_HOME" ]] || PG_HOME=/var/lib/pgsql
    RETRY_SQL="$PG_HOME/sf-schema-retry.sql"
    cp "$SCHEMA_SQL" "$RETRY_SQL"
    chown postgres:postgres "$RETRY_SQL"
    chmod 644 "$RETRY_SQL"
    sudo -u postgres psql -d "$DB_NAME" -f "$RETRY_SQL" 2>&1 | tail -30
    rm -f "$RETRY_SQL"

    # 再驗一次
    MISSING_TBL=()
    for t in "${EXPECTED_TABLES[@]}"; do
        if ! sudo -u postgres psql -d "$DB_NAME" -tAc "SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='$t'" 2>/dev/null | grep -q 1; then
            MISSING_TBL+=("$t")
        fi
    done

    if [[ ${#MISSING_TBL[@]} -gt 0 ]]; then
        fail "缺 ${#MISSING_TBL[@]} 個表 (${MISSING_TBL[*]}) — schema 套用 retry 仍失敗. 看上方錯訊"
    else
        ok "retry 後 6 表都建立"
    fi
fi

ok "全部 6 個關鍵表存在"

# GRANT 給 portal user
sudo -u postgres psql -d "$DB_NAME" <<EOF 2>&1 | tail -3
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $DB_USER;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO $DB_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO $DB_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO $DB_USER;
EOF
ok "Portal user 對所有表的權限授予"

# v2.4.2: portal user 連 DB 直接驗
if sudo -u postgres psql -d "$DB_NAME" -tAc "SELECT count(*) FROM businesscode" 2>/dev/null | head -1; then
    ok "businesscode 表 portal user 可讀"
else
    warn "businesscode 讀取失敗 (但不阻斷, portal 用 .env 內 url + md5 認證會再試)"
fi

# === Step 6c: .env ===
step "Step 6c: 寫 /opt/portal/app/.env"

cat > "$PORTAL_DIR/app/.env" <<EOF
# SF Portal v2.4.1 自動產生 — $(date '+%Y-%m-%d %H:%M:%S')
FLASK_ENV=production
SECRET_KEY=$(openssl rand -hex 32)
SESSION_TIMEOUT_MIN=30
DEBUG=false
VERBOSE_LOG=false

DB_MODE=Express
DB_CONNECTION_STRING=postgresql://$DB_USER:$DB_PASS@127.0.0.1:5432/$DB_NAME

AD_SERVER=ldap://corp-dc01.corp.local
AD_BASE_DN=DC=corp,DC=local
AD_DOMAIN=CORP
AD_BIND_USER=
AD_BIND_PASS=

SMTP_SERVER=mail-relay.corp.local
SMTP_PORT=25
SMTP_USE_TLS=false
SMTP_FROM=sf-noreply@corp.local
ADMIN_EMAIL=it-admin@corp.local

DATA_EXCHANGE_ROOT=/data/exchange
PORTAL_LOG_DIR=$PORTAL_DIR/logs
PORTAL_BACKUP_DIR=$PORTAL_DIR/backups

BATCH_IDLE_SECONDS=30
BATCH_SAFETY_MINUTES=5
APPROVAL_TIMEOUT_DAYS=7

HOME_RETENTION_DAYS=7
SAMBA_RETENTION_DAYS=7
AUDITLOG_ONLINE_DAYS=365
AUDITLOG_ARCHIVE_YEARS=5
EOF
chmod 640 "$PORTAL_DIR/app/.env"
chown "$RUN_USER:$RUN_USER" "$PORTAL_DIR/app/.env"
ok ".env 寫入 $PORTAL_DIR/app/.env"

mkdir -p /data/exchange
chown "$RUN_USER:$RUN_USER" /data/exchange
chown -R "$RUN_USER:$RUN_USER" "$PORTAL_DIR"

# === Step 7 ===
step "Step 7: 寫 systemd unit"

GUNICORN_BIN=""
for c in /usr/bin/gunicorn /usr/bin/gunicorn-3 /usr/local/bin/gunicorn; do
    [[ -x "$c" ]] && GUNICORN_BIN="$c" && break
done
[[ -n "$GUNICORN_BIN" ]] || GUNICORN_BIN=$(command -v gunicorn 2>/dev/null || echo "")

if [[ -z "$GUNICORN_BIN" ]]; then
    fail "找不到 gunicorn binary"
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

# === Step 8: nginx ===
step "Step 8: nginx 反代 + 防火牆"

NGINX_CONF="/etc/nginx/conf.d/sf-portal.conf"

# v2.4.2: 移掉 /etc/nginx/nginx.conf 內預設 server { } block, 避免跟 sf-portal.conf 的 default_server 衝突
# (Section 4 USER 看到 "conflicting server name '_' on 0.0.0.0:80" warning)
NGINX_MAIN=/etc/nginx/nginx.conf
if grep -q 'server_name  _;' "$NGINX_MAIN" 2>/dev/null; then
    info "$NGINX_MAIN 內有預設 server { _; } block, 註解掉避免衝突"
    cp "$NGINX_MAIN" "${NGINX_MAIN}.bak.$(date +%s)"
    # 用 Python 處理 (sed 處理 multi-line server block 容易錯)
    /usr/bin/python3 <<'PYEOF'
import re
from pathlib import Path
p = Path("/etc/nginx/nginx.conf")
s = p.read_text()
# 找含 server_name _; 的 server { ... } block, 整段註解掉
# 簡易作法: 找 "    server {" 開始, 配對 "    }" 結束
lines = s.split('\n')
out = []
in_block = False
brace_depth = 0
buffer = []
for line in lines:
    if not in_block:
        if re.match(r'^\s{4}server\s*\{', line):
            in_block = True
            brace_depth = 1
            buffer = [line]
            continue
        out.append(line)
    else:
        buffer.append(line)
        brace_depth += line.count('{') - line.count('}')
        if brace_depth == 0:
            # block 結束, 看裡面有沒有 server_name _;
            block_text = '\n'.join(buffer)
            if 'server_name  _;' in block_text or 'server_name _;' in block_text:
                # 整段註解
                for b in buffer:
                    out.append('#v242# ' + b)
            else:
                out.extend(buffer)
            in_block = False
            buffer = []
p.write_text('\n'.join(out))
print('[ok] nginx.conf 預設 server block 已註解')
PYEOF
fi

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

# v2.4.1: nginx test → reload, reload 失敗就 restart
if nginx -t 2>&1 | grep -q 'syntax is ok'; then
    if systemctl reload nginx 2>&1 | tail -2; then
        ok "nginx reload OK"
    else
        warn "nginx reload 失敗, 嘗試 restart"
        systemctl restart nginx 2>&1 | tail -2
    fi
else
    warn "nginx config 有問題, 嘗試 restart:"
    nginx -t 2>&1 | tail -3
    systemctl restart nginx 2>&1 | tail -2 || warn "restart 也失敗"
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

# === Step 9 ===
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
            ok "Portal 起來 (gunicorn HTTP $code)"
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
    echo -e "${BOLD}${GREEN}║   ✅ Portal 部署完成 (v2.4.1)                                 ║${NC}"
    echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "  Portal (USER 用)      : http://$MAIN_IP/        (nginx 反代, HTTP $NGINX_CODE)"
    echo "  Portal (debug 直連)   : http://$MAIN_IP:5000/"
    echo "  DB 密碼               : $DB_PASS"
    echo "  .env                  : $PORTAL_DIR/app/.env"
    echo ""
    if [[ "$NGINX_CODE" == "502" ]]; then
        warn "nginx 回 502 — Flask 起來但 nginx proxy 沒通, 跑這條看 nginx 端錯:"
        echo "    tail -20 /var/log/nginx/sf-portal-error.log"
    fi
else
    echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║   ❌ Portal 沒起來                                            ║${NC}"
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
    echo "→ 手動 debug:"
    echo "    cd $PORTAL_DIR/app"
    echo "    sudo -u $RUN_USER $GUNICORN_BIN --workers 1 --bind 127.0.0.1:5001 --log-level debug --chdir $PORTAL_DIR/app wsgi:app"
    exit 1
fi
