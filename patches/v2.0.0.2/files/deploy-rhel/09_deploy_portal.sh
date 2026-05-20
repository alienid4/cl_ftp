#!/bin/bash
# 部署 Flask Portal + systemd service
# 對應 Windows: deploy/09_setup_portal.ps1 (但 RHEL 用 systemd 而非 NSSM)
set -euo pipefail

PORTAL="${SF_PORTAL_ROOT:-/opt/portal}"
PORTAL_PORT="${SF_PORTAL_PORT:-5000}"
DB_NAME="${SF_DB_NAME:-file_exchange_audit}"
DB_USER="${SF_DB_USER:-portal}"
DB_PASS="${SF_DB_PASS:-changeme}"

echo "=== 部署 Flask Portal ==="

# 1. 確認 Python 3.11
if ! command -v python3.11 &>/dev/null && ! command -v python3 &>/dev/null; then
    dnf install -y python3 python3-pip python3-virtualenv
fi
PYTHON=$(command -v python3.11 || command -v python3)
echo "[ok] Python: $($PYTHON --version)"

# 2. 拷 portal/ 程式到 $PORTAL/app
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO_ROOT/portal"
if [[ ! -d "$SRC" ]]; then
    echo "[FAIL] $SRC 不存在"
    exit 1
fi

rsync -a --delete "$SRC/" "$PORTAL/app/"
chown -R portal:portal "$PORTAL/app"
echo "[ok] Portal 程式碼複製"

# 3. 建立虛擬環境 + 裝套件
VENV="$PORTAL/venv"
if [[ ! -d "$VENV" ]]; then
    sudo -u portal $PYTHON -m venv "$VENV"
    echo "[ok] venv 建立"
fi

# pip install (自動偵測離線 wheels, 沒有再走 pypi)
REQ="$PORTAL/app/requirements.txt"

# 多路徑找 wheels 目錄 (對應 Windows v1.0.0.10 的離線 fallback)
WHEELS=""
for w in /opt/sf/python_wheels /opt/python_wheels "$REPO_ROOT/../wheels" "$REPO_ROOT/wheels"; do
    if [[ -d "$w" ]] && ls "$w"/*.whl &>/dev/null; then
        WHEELS="$w"
        break
    fi
done

if [[ -f "$REQ" ]]; then
    if [[ -n "$WHEELS" ]]; then
        echo "[info] 使用本地 wheels: $WHEELS ($(ls $WHEELS/*.whl 2>/dev/null | wc -l) 檔)"
        sudo -u portal "$VENV/bin/pip" install --no-index --find-links "$WHEELS" --upgrade pip 2>&1 | tail -3
        sudo -u portal "$VENV/bin/pip" install --no-index --find-links "$WHEELS" -r "$REQ" 2>&1 | tail -5
        # 加 PostgreSQL 驅動
        sudo -u portal "$VENV/bin/pip" install --no-index --find-links "$WHEELS" psycopg2-binary gunicorn 2>&1 | tail -3
        echo "[ok] Python 套件安裝 (offline)"
    else
        echo "[info] 沒找到 local wheels, 走 pypi (需外網)"
        sudo -u portal "$VENV/bin/pip" install --upgrade pip 2>&1 | tail -3
        sudo -u portal "$VENV/bin/pip" install -r "$REQ" 2>&1 | tail -5
        sudo -u portal "$VENV/bin/pip" install psycopg2-binary gunicorn 2>&1 | tail -3
        echo "[ok] Python 套件安裝 (online)"
    fi
else
    echo "[warn] requirements.txt 不存在"
fi

# 4. 寫 appsettings.json
cat > "$PORTAL/app/appsettings.json" <<EOF
{
  "DATABASE_URL": "postgresql://$DB_USER:$DB_PASS@127.0.0.1/$DB_NAME",
  "PORTAL_PORT": $PORTAL_PORT,
  "DATA_ROOT": "${SF_DATA_ROOT:-/data/exchange}",
  "LOG_DIR": "/var/log/sf-portal",
  "AD_DOMAIN": "${SF_AD_DOMAIN:-corp.local}",
  "SECRET_KEY": "$(openssl rand -hex 32)"
}
EOF
chmod 640 "$PORTAL/app/appsettings.json"
chown portal:portal "$PORTAL/app/appsettings.json"
echo "[ok] appsettings.json"

# 5. 寫 systemd unit (取代 NSSM)
cat > /etc/systemd/system/sf-portal.service <<EOF
[Unit]
Description=SF File Exchange Portal (Flask)
After=network.target postgresql.service

[Service]
Type=simple
User=portal
Group=portal
WorkingDirectory=$PORTAL/app
Environment="PATH=$VENV/bin"
ExecStart=$VENV/bin/gunicorn --workers 3 --bind 127.0.0.1:$PORTAL_PORT 'wsgi:application'
Restart=always
RestartSec=10

StandardOutput=append:/var/log/sf-portal/stdout.log
StandardError=append:/var/log/sf-portal/stderr.log

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now sf-portal
echo "[ok] systemd unit sf-portal $(systemctl is-active sf-portal)"

# 6. 驗證
sleep 2
if curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:$PORTAL_PORT/ | grep -qE '^(200|302|401)$'; then
    echo "[ok] Portal HTTP 回應正常"
else
    echo "[warn] Portal HTTP 沒回應, 看 log: journalctl -u sf-portal -n 50"
fi

echo ""
echo "Portal 部署完成"
echo "Log: journalctl -u sf-portal -f"
echo "或 tail -f /var/log/sf-portal/stdout.log"
