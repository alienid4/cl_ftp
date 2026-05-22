#!/bin/bash
#
# diag-502-v2.4.1.sh — SF Portal 502 Bad Gateway 一鍵診斷
#
# 用法 (SF 主機):
#   sudo bash /tmp/ftp-lab/diag-502-v2.4.1.sh
#
# 一次撈所有相關資訊, 截圖貼給 Claude/GPT 即可診斷.

CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
sec() { echo ""; echo -e "${CYAN}=== $* ===${NC}"; }

sec "1. sf-portal 服務狀態"
systemctl status sf-portal --no-pager -l 2>&1 | head -25

sec "2. gunicorn 是否 listen 5000"
ss -tlnp 2>&1 | grep -E '5000|5432|80\s' || echo "(無 5000/5432/80 listen)"

sec "3. nginx 服務狀態"
systemctl status nginx --no-pager -l 2>&1 | head -10

sec "4. nginx config 測試"
nginx -t 2>&1

sec "5. /opt/portal/logs/error.log 最後 40 行"
tail -40 /opt/portal/logs/error.log 2>&1 || echo "(無 error.log)"

sec "6. /opt/portal/logs/portal-stderr.log 最後 20 行"
tail -20 /opt/portal/logs/portal-stderr.log 2>&1 || echo "(無 portal-stderr.log)"

sec "7. /var/log/nginx/sf-portal-error.log 最後 20 行"
tail -20 /var/log/nginx/sf-portal-error.log 2>&1 || echo "(無 nginx error)"

sec "8. journalctl -u sf-portal 最後 30 行"
journalctl -u sf-portal -n 30 --no-pager 2>&1

sec "9. SELinux 狀態 + AVC denials"
echo "getenforce: $(getenforce 2>&1)"
echo ""
echo "--- 最近 10 分鐘 AVC denied ---"
ausearch -m AVC --start recent 2>&1 | head -30 || echo "(無 AVC)"
echo ""
echo "--- httpd_can_network_connect 設定 ---"
getsebool httpd_can_network_connect 2>&1

sec "10. 直接 curl 測 (gunicorn / nginx 端)"
echo "--- curl 127.0.0.1:5000 (gunicorn 直連) ---"
curl -sI -m 3 http://127.0.0.1:5000/ 2>&1 | head -3
echo ""
echo "--- curl 127.0.0.1:80 (nginx 反代) ---"
curl -sI -m 3 http://127.0.0.1/ 2>&1 | head -3

sec "11. 防火牆狀態"
firewall-cmd --list-all 2>&1 | head -15

sec "12. .env 關鍵設定 (打碼後)"
if [[ -f /opt/portal/app/.env ]]; then
    grep -E '^(DB_CONNECTION_STRING|DATA_EXCHANGE_ROOT|PORTAL_LOG_DIR|AD_DOMAIN)=' /opt/portal/app/.env | sed 's|:[^@]*@|:****@|g'
else
    echo "(無 .env)"
fi

sec "13. DB 連線測試"
sudo -u postgres psql -d file_exchange_audit -tAc "SELECT 'DB OK', count(*) FROM businesscode" 2>&1 | head -3

sec "14. Python import 測試 (nginx user)"
sudo -u nginx /usr/bin/python3 -c "
import sys
print('Python:', sys.version)
print('sys.path:', sys.path[:5])
from flask import Flask
print('flask OK')
from flask_login import LoginManager
print('flask_login OK')
from dotenv import load_dotenv
print('dotenv OK')
import psycopg2
print('psycopg2 OK')
import ldap3
print('ldap3 OK')
" 2>&1 | head -20

sec "15. 手動 gunicorn 啟動測試 (5001 port, 3 秒)"
cd /opt/portal/app
timeout 5 sudo -u nginx /usr/bin/gunicorn --workers 1 --bind 127.0.0.1:5001 --log-level debug --chdir /opt/portal/app wsgi:app 2>&1 | head -40 || echo "(timeout/Ctrl+C OK)"

echo ""
echo -e "${GREEN}=== 診斷完成 ===${NC}"
echo "截圖完整輸出貼給 Claude/GPT, 不要漏掉任何 section."
