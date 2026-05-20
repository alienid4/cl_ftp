#!/bin/bash
# SF 主機健康速查 — Linux 版
# 對應 Windows: scripts/health_check.ps1
set +e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

ok()   { echo -e "${GREEN}[ OK ]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; }
warn() { echo -e "${YELLOW}[warn]${NC} $*"; }

echo "=== SF 主機健康速查 ($(date)) ==="
echo "主機: $(hostname)"
echo ""

# === 1. 核心服務 ===
echo "--- 服務 (對應 systemctl status) ---"
for svc in sshd nginx postgresql sf-portal smb chronyd firewalld auditd; do
    if systemctl is-active --quiet $svc 2>/dev/null; then
        ok "$svc: $(systemctl is-active $svc) / $(systemctl is-enabled $svc 2>/dev/null)"
    else
        fail "$svc: $(systemctl is-active $svc 2>/dev/null || echo not-installed)"
    fi
done

echo ""
echo "--- Port 監聽 (對應 ss -tlnp) ---"
for p in 22 80 443 5000 5432 445 139; do
    if ss -tln 2>/dev/null | awk '{print $4}' | grep -q ":$p$"; then
        ok "Port $p"
    else
        warn "Port $p (未監聽)"
    fi
done

echo ""
echo "--- 系統資源 ---"
echo -n "CPU 使用率: "; top -bn1 | grep '%Cpu' | awk '{print 100-$8"%"}'
echo -n "記憶體:    "; free -h | awk '/Mem/{print $3 "/" $2}'
echo -n "Disk /:    "; df -h / | awk 'NR==2{print $3 "/" $2 " (" $5 ")"}'
echo -n "Disk /data:"; df -h /data 2>/dev/null | awk 'NR==2{print $3 "/" $2 " (" $5 ")"}'
echo -n "Disk /opt: "; df -h /opt 2>/dev/null | awk 'NR==2{print $3 "/" $2 " (" $5 ")"}'

echo ""
echo "--- NTP 同步 (對應 chronyc tracking) ---"
chronyc tracking 2>/dev/null | grep -E 'Reference|Stratum|Last offset' || warn "chronyd 沒設"

echo ""
echo "--- AD 整合 (對應 realm list) ---"
if command -v realm &>/dev/null; then
    realm list 2>/dev/null || warn "未加入 AD domain"
else
    warn "realm 未安裝"
fi

echo ""
echo "--- 排程工作 (對應 crontab -l + systemd timers) ---"
ls /etc/cron.d/sf-* 2>/dev/null && ok "找到 SF cron 任務"

echo ""
echo "--- 防火牆規則 (對應 firewall-cmd --list-all) ---"
firewall-cmd --zone=sf --list-services 2>/dev/null || firewall-cmd --list-services 2>/dev/null

echo ""
echo "--- Portal HTTP 測試 ---"
PORTAL_PORT="${SF_PORTAL_PORT:-5000}"
if response=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:$PORTAL_PORT/ -m 5 2>/dev/null); then
    case "$response" in
        200|302|401) ok "Portal HTTP $response (健康)" ;;
        *) warn "Portal HTTP $response (異常)" ;;
    esac
else
    fail "Portal 沒回應"
fi

echo ""
echo "--- DB 連線 ---"
if sudo -u portal /opt/portal/venv/bin/python -c "
import psycopg2
import json
with open('/opt/portal/app/appsettings.json') as f:
    conf = json.load(f)
conn = psycopg2.connect(conf['DATABASE_URL'])
cur = conn.cursor()
cur.execute('SELECT COUNT(*) FROM audit_log')
print('AuditLog 筆數:', cur.fetchone()[0])
" 2>&1 | tail -3; then
    ok "DB 連線 OK"
else
    fail "DB 連線失敗"
fi

echo ""
echo "--- 近 24 小時 SFTP 認證失敗 ---"
fails=$(journalctl -u sshd --since '24 hours ago' 2>/dev/null | grep -c 'Failed password' || echo 0)
[ "$fails" -lt 20 ] && ok "SFTP 失敗 $fails 次" || warn "SFTP 失敗 $fails 次 (可能暴力破解)"

echo ""
echo "--- 訪問網址 ---"
IP=$(ip -4 addr | grep 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}' | cut -d/ -f1)
if [ -n "$IP" ]; then
    echo "  Portal : http://$IP/  (nginx 80) 或 http://$IP:$PORTAL_PORT/ (直接 Flask)"
    echo "  SFTP   : sftp <user>@$IP"
    echo "  SMB    : smb://$IP/<share>"
fi

echo ""
echo "完成。詳細 log: journalctl -u <service> -f"
