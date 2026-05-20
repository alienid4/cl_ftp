#!/bin/bash
# 安裝 nginx (取代 IIS)
# 對應 Windows: deploy/06_install_iis.ps1
set -euo pipefail

PORTAL="${SF_PORTAL_ROOT:-/opt/portal}"
PORTAL_PORT="${SF_PORTAL_PORT:-5000}"

echo "=== 安裝 nginx ==="

# 1. 裝 nginx
if ! rpm -q nginx &>/dev/null; then
    dnf install -y nginx
fi
echo "[ok] nginx installed"

# 2. 套設定檔
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$REPO_ROOT/config/nginx/sf-portal.conf"

if [[ -f "$TEMPLATE" ]]; then
    cp "$TEMPLATE" /etc/nginx/conf.d/sf-portal.conf
    echo "[ok] sf-portal.conf 套用"
else
    # Fallback: 簡單 conf
    cat > /etc/nginx/conf.d/sf-portal.conf <<EOF
server {
    listen 80;
    server_name _;

    # 反向代理到 Portal Flask (port 5000)
    location / {
        proxy_pass http://127.0.0.1:$PORTAL_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # 靜態檔
    location /static/ {
        alias $PORTAL/app/static/;
    }
}
EOF
    echo "[ok] 用 fallback 設定"
fi

# 3. 移除 default server (避免衝突)
[[ -f /etc/nginx/conf.d/default.conf ]] && mv /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/default.conf.disabled

# 4. 驗證設定
if nginx -t 2>&1; then
    echo "[ok] nginx 設定 OK"
else
    echo "[FAIL] nginx 設定錯誤"
    exit 1
fi

# 5. 啟動
systemctl enable --now nginx
systemctl restart nginx
echo "[ok] nginx $(systemctl is-active nginx)"

# 6. SELinux 允許 nginx proxy 到 portal
setsebool -P httpd_can_network_connect 1 2>/dev/null || true

echo ""
echo "nginx 部署完成"
systemctl status nginx --no-pager -l | head -8
