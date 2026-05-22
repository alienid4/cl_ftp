#!/bin/bash
#
# diagnose.sh — Portal 訪問不通時的完整診斷
#
# 用法 (從 SF 主機, root):
#   curl -fsSL https://github.com/alienid4/cl_ftp/raw/main/deploy-rhel/diagnose.sh | sudo bash
#
# 對應 Windows 版 scripts/diagnose_portal.ps1
#
# 跑完印一份「狀態報告」+「最可能原因」+「對應修法 URL」
#

set +e   # 不要因為單個 check fail 就 abort, 我們要看所有

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
BOLD='\033[1m'

ok()    { echo -e "${GREEN}[ OK ]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[warn]${NC}  $*"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $*"; }
info()  { echo -e "${CYAN}[info]${NC}  $*"; }

echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║   SF Portal Diagnose — Portal 訪問不通的完整排查              ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

REASONS=()
NEXT_ACTIONS=()

# === 1. Service 狀態 ===
echo -e "${BOLD}=== 1. Service 狀態 (對應 systemctl status) ===${NC}"
for svc in sshd nginx postgresql sf-portal; do
    if systemctl list-unit-files | grep -q "^$svc.service"; then
        if systemctl is-active $svc &>/dev/null; then
            ok "$svc: $(systemctl is-active $svc) / $(systemctl is-enabled $svc 2>/dev/null)"
        else
            fail "$svc: $(systemctl is-active $svc 2>/dev/null) (應該 Running)"
            REASONS+=("$svc service 沒跑")
        fi
    else
        fail "$svc: service unit 不存在"
        REASONS+=("$svc systemd unit 沒建立 (對應 install_all.sh 內 install 該 service 那步沒跑或 fail)")
    fi
done

# === 2. Port 監聽 ===
echo ""
echo -e "${BOLD}=== 2. Port 監聽 (對應 ss -tlnp) ===${NC}"
for p in 22 80 443 5000 5432; do
    line=$(ss -tlnp 2>/dev/null | grep -E ":$p\b" | head -1)
    if [[ -n "$line" ]]; then
        addr=$(echo "$line" | awk '{print $4}')
        proc=$(echo "$line" | grep -oE 'users:\(\([^)]+\)' | head -1)
        ok "Port $p: $addr $proc"
    else
        warn "Port $p: 沒監聽"
    fi
done

# === 3. Portal 程式碼 / venv ===
echo ""
echo -e "${BOLD}=== 3. Portal 程式碼 / venv ===${NC}"
PORTAL_DIRS=("/opt/portal/app" "/opt/portal/venv" "/opt/sf/portal" "/opt/sf")
for d in "${PORTAL_DIRS[@]}"; do
    if [[ -d "$d" ]]; then
        ok "$d 存在"
    fi
done

if [[ -f /opt/portal/app/wsgi.py ]]; then
    ok "/opt/portal/app/wsgi.py 存在 (Portal 入口)"
else
    fail "/opt/portal/app/wsgi.py 不存在 (Portal 沒部署)"
    REASONS+=("Portal 程式碼沒拷到 /opt/portal/app")
fi

if [[ -f /opt/portal/venv/bin/python ]]; then
    pyver=$(/opt/portal/venv/bin/python --version 2>&1)
    ok "venv Python: $pyver"

    if /opt/portal/venv/bin/python -c "import flask; print('flask', flask.__version__)" 2>&1 | grep -q flask; then
        ok "Flask 已裝: $(/opt/portal/venv/bin/python -c "import flask; print(flask.__version__)" 2>&1)"
    else
        fail "Flask 沒裝 (pip install 失敗)"
        REASONS+=("Python venv 內缺 Flask")
    fi

    if /opt/portal/venv/bin/python -c "import waitress" 2>&1 | grep -qv 'No module'; then
        ok "waitress 已裝"
    else
        warn "waitress 沒裝"
    fi

    if [[ -f /opt/portal/venv/bin/gunicorn ]]; then
        ok "gunicorn 已裝"
    else
        warn "gunicorn 沒裝 (Portal service 跑不起來)"
        REASONS+=("gunicorn 沒裝, sf-portal.service 跑不了")
    fi
else
    fail "/opt/portal/venv 不存在 (Python venv 沒建)"
    REASONS+=("Python venv 沒建立")
fi

# === 4. systemd unit ===
echo ""
echo -e "${BOLD}=== 4. systemd unit ===${NC}"
if [[ -f /etc/systemd/system/sf-portal.service ]]; then
    ok "sf-portal.service unit 存在"
    echo "  ExecStart:"
    grep -E '^(ExecStart|WorkingDirectory|User)=' /etc/systemd/system/sf-portal.service | sed 's/^/    /'
else
    fail "/etc/systemd/system/sf-portal.service 不存在"
    REASONS+=("systemd unit 沒寫 (對應 09_deploy_portal.sh 沒跑完)")
fi

# === 5. Portal log ===
echo ""
echo -e "${BOLD}=== 5. Portal 最近 log (對應 journalctl -u sf-portal) ===${NC}"
if systemctl list-unit-files | grep -q "^sf-portal.service"; then
    journalctl -u sf-portal -n 30 --no-pager 2>&1 | tail -30 | sed 's/^/  /'
else
    info "(sf-portal unit 不存在, 沒 log)"
fi

# === 6. nginx config / log ===
echo ""
echo -e "${BOLD}=== 6. nginx 設定 + log ===${NC}"
if nginx -t 2>&1 | grep -q 'syntax is ok'; then
    ok "nginx config syntax OK"
else
    fail "nginx config 有問題:"
    nginx -t 2>&1 | sed 's/^/    /'
    REASONS+=("nginx config 語法錯誤")
fi

if [[ -f /var/log/nginx/sf-portal-error.log ]]; then
    echo "  最近 10 行 sf-portal-error.log:"
    tail -10 /var/log/nginx/sf-portal-error.log 2>&1 | sed 's/^/    /' || echo "    (空)"
fi
if [[ -f /var/log/nginx/error.log ]]; then
    echo "  最近 10 行 nginx error.log:"
    tail -10 /var/log/nginx/error.log 2>&1 | sed 's/^/    /' || echo "    (空)"
fi

# === 7. firewall ===
echo ""
echo -e "${BOLD}=== 7. 防火牆 ===${NC}"
if systemctl is-active firewalld &>/dev/null; then
    info "firewalld 在跑, 看放行哪些:"
    firewall-cmd --list-services 2>&1 | sed 's/^/    services: /'
    firewall-cmd --list-ports 2>&1 | sed 's/^/    ports:    /'
    if firewall-cmd --list-ports 2>/dev/null | grep -q '5000\|80'; then
        ok "防火牆放行 portal port"
    else
        warn "防火牆可能沒放行 5000 / 80"
    fi
fi

# === 8. SELinux ===
echo ""
echo -e "${BOLD}=== 8. SELinux ===${NC}"
selinux=$(getenforce 2>/dev/null || echo "Disabled")
echo "  狀態: $selinux"
if [[ "$selinux" == "Enforcing" ]]; then
    # 看最近 10 個 AVC denials
    denials=$(ausearch -m AVC --start recent 2>/dev/null | tail -30)
    if [[ -n "$denials" ]]; then
        warn "有 SELinux AVC 拒絕記錄 (前 5 行):"
        echo "$denials" | head -10 | sed 's/^/    /'
        REASONS+=("SELinux 阻擋 (見上方 AVC denials)")
    else
        ok "SELinux Enforcing, 沒 AVC denial"
    fi
fi

# === 9. DB 連線 ===
echo ""
echo -e "${BOLD}=== 9. DB 連線 ===${NC}"
if systemctl is-active postgresql &>/dev/null; then
    db_check=$(sudo -u portal /opt/portal/venv/bin/python -c "
import psycopg2, json
try:
    with open('/opt/portal/app/appsettings.json') as f:
        c = json.load(f)
    conn = psycopg2.connect(c['DATABASE_URL'])
    cur = conn.cursor()
    cur.execute('SELECT COUNT(*) FROM audit_log')
    print('OK', cur.fetchone()[0])
except Exception as e:
    print('FAIL', str(e)[:100])
" 2>&1)
    if [[ "$db_check" == OK* ]]; then
        ok "DB 連線 OK ($db_check)"
    else
        warn "DB 連線: $db_check"
    fi
fi

# === 結論 + 下一步 ===
echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║   診斷總結                                                    ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

if [[ ${#REASONS[@]} -eq 0 ]]; then
    ok "所有檢查通過, 應該能訪問 Portal"
    echo ""
    MAIN_IP=$(ip -4 addr | grep -E 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}' | cut -d/ -f1)
    echo "訪問網址 (從別台 PC):"
    echo "  http://$MAIN_IP/"
    echo "  http://$MAIN_IP:5000/"
else
    echo -e "${RED}找到 ${#REASONS[@]} 個問題:${NC}"
    for r in "${REASONS[@]}"; do
        echo "  ✗ $r"
    done

    echo ""
    echo -e "${YELLOW}建議下一步:${NC}"
    echo ""
    echo "  1. 重跑部署 (補裝 + 補 service):"
    echo "     URL: https://github.com/alienid4/cl_ftp/raw/main/release-zip/latest-install.sh"
    echo ""
    echo "  2. 或單獨補 Portal 部分:"
    echo "     URL: https://github.com/alienid4/cl_ftp/raw/main/deploy-rhel/09_deploy_portal.sh"
    echo ""
    echo "  3. 把本診斷輸出截圖貼給 Claude (記錄這 ${#REASONS[@]} 個問題)"
fi

echo ""
