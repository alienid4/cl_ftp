#!/bin/bash
# 安裝 PostgreSQL + 建 schema (取代 SQL Server Express)
# 對應 Windows: deploy/08_install_sqlexpress_notes.ps1 + sql/01_create_db.sql
set -euo pipefail

DB_NAME="${SF_DB_NAME:-file_exchange_audit}"
DB_USER="${SF_DB_USER:-portal}"
DB_PASS="${SF_DB_PASS:-changeme}"

echo "=== 安裝 PostgreSQL ==="

# 1. 裝 postgresql-server
if ! rpm -q postgresql-server &>/dev/null; then
    dnf install -y postgresql-server postgresql-contrib python3-psycopg2
fi
echo "[ok] postgresql-server installed"

# 2. 初始化 (只第一次)
if [[ ! -f /var/lib/pgsql/data/PG_VERSION ]]; then
    postgresql-setup --initdb
    echo "[ok] DB 初始化"
fi

# 3. 啟動
systemctl enable --now postgresql
echo "[ok] postgresql $(systemctl is-active postgresql)"

# 4. 建 DB + User
sudo -u postgres psql <<EOF
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_database WHERE datname = '$DB_NAME') THEN
        CREATE DATABASE $DB_NAME;
    END IF;
END \$\$;

DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_user WHERE usename = '$DB_USER') THEN
        CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';
    ELSE
        ALTER USER $DB_USER WITH PASSWORD '$DB_PASS';
    END IF;
END \$\$;

GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;
EOF
echo "[ok] DB '$DB_NAME' + User '$DB_USER'"

# 5. 套 schema
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEMA="$REPO_ROOT/sql/01_create_db_postgres.sql"
if [[ -f "$SCHEMA" ]]; then
    sudo -u postgres psql -d "$DB_NAME" < "$SCHEMA"
    echo "[ok] schema 套用"
else
    echo "[warn] $SCHEMA 不存在, 之後跑: psql -U postgres -d $DB_NAME < schema.sql"
fi

# 6. 改 pg_hba.conf 允許 portal 連 (localhost only)
PG_HBA="/var/lib/pgsql/data/pg_hba.conf"
if ! grep -q "^host.*$DB_NAME.*$DB_USER.*127.0.0.1" "$PG_HBA" 2>/dev/null; then
    echo "host    $DB_NAME    $DB_USER    127.0.0.1/32    md5" >> "$PG_HBA"
    echo "host    $DB_NAME    $DB_USER    ::1/128         md5" >> "$PG_HBA"
    systemctl reload postgresql
    echo "[ok] pg_hba.conf 允許 portal 連"
fi

echo ""
echo "PostgreSQL 設定完成"
echo "連線測試:"
echo "  psql -h localhost -U $DB_USER -d $DB_NAME"
echo "  (密碼: \$SF_DB_PASS = $DB_PASS)"
