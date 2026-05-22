#!/bin/bash
#
# repo_check.sh — 確認 SF 主機可用 repo + 找 Python 套件來源
#
# 用法:
#   curl -fsSL https://github.com/alienid4/cl_ftp/raw/main/deploy-rhel/repo_check.sh | sudo bash
#
# 結果幫你決定 Portal 該怎麼裝 (CRB / pip / mod_wsgi)
#

set +e

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
BOLD='\033[1m'

ok()    { echo -e "${GREEN}[ OK ]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[warn]${NC}  $*"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $*"; }
info()  { echo -e "${CYAN}[info]${NC}  $*"; }

echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║   repo_check.sh — 確認 SF 主機能用啥 repo                     ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# === 1. 列 enabled repo ===
echo -e "${BOLD}=== 1. 目前 enabled 的 repo ===${NC}"
dnf repolist 2>&1 | sed 's/^/  /'

# === 2. 檢查關鍵 repo 是否 enabled ===
echo ""
echo -e "${BOLD}=== 2. 關鍵 repo 狀態 ===${NC}"
ENABLED_REPOS=$(dnf repolist 2>/dev/null)

for r in baseos appstream codeready epel; do
    if echo "$ENABLED_REPOS" | grep -iq "$r"; then
        ok "$r repo enabled"
    else
        warn "$r repo 沒 enabled"
    fi
done

# === 3. 找 python3-flask 在哪 ===
echo ""
echo -e "${BOLD}=== 3. 找 python3-flask 可不可裝 ===${NC}"
FLASK_INFO=$(dnf info python3-flask 2>&1)
if echo "$FLASK_INFO" | grep -q "^Available Packages"; then
    repo=$(echo "$FLASK_INFO" | grep -m1 "^From repo" | awk '{print $NF}')
    ok "python3-flask 找得到, 在 repo: $repo"
elif echo "$FLASK_INFO" | grep -q "^Installed Packages"; then
    ok "python3-flask 已經裝過"
else
    fail "python3-flask 找不到 (要 enable EPEL 或 CRB 或走 pip)"
fi

# === 4. 找 python3-werkzeug ===
echo ""
echo -e "${BOLD}=== 4. 找 python3-werkzeug ===${NC}"
WERK_INFO=$(dnf info python3-werkzeug 2>&1)
if echo "$WERK_INFO" | grep -q "^Available\|^Installed"; then
    repo=$(echo "$WERK_INFO" | grep -m1 "^From repo" | awk '{print $NF}')
    ok "python3-werkzeug 找得到 (repo: $repo)"
else
    warn "python3-werkzeug 找不到"
fi

# === 5. 找 python3-psycopg2 (DB driver, 一定要的) ===
echo ""
echo -e "${BOLD}=== 5. 找 python3-psycopg2 (PostgreSQL driver) ===${NC}"
PSY_INFO=$(dnf info python3-psycopg2 2>&1)
if echo "$PSY_INFO" | grep -q "^Available\|^Installed"; then
    repo=$(echo "$PSY_INFO" | grep -m1 "^From repo" | awk '{print $NF}')
    ok "python3-psycopg2 找得到 (repo: $repo)"
else
    fail "python3-psycopg2 找不到 (這個一定要, 沒它 Portal 連不到 DB)"
fi

# === 6. 找 mod_wsgi (Plan C 用) ===
echo ""
echo -e "${BOLD}=== 6. 找 python3-mod_wsgi (Plan C: httpd + mod_wsgi) ===${NC}"
MWS_INFO=$(dnf info python3-mod_wsgi 2>&1)
if echo "$MWS_INFO" | grep -q "^Available\|^Installed"; then
    repo=$(echo "$MWS_INFO" | grep -m1 "^From repo" | awk '{print $NF}')
    ok "python3-mod_wsgi 找得到 (repo: $repo) — Plan C 可行"
else
    warn "python3-mod_wsgi 找不到"
fi

# === 7. 測 pip 能不能連 PyPI ===
echo ""
echo -e "${BOLD}=== 7. 測 pip 能不能連 PyPI ===${NC}"
if ! command -v pip3 &>/dev/null; then
    warn "pip3 沒裝, 先裝: dnf install -y python3-pip"
    PIP_OK=false
else
    if pip3 install --dry-run --quiet Flask 2>&1 | grep -qE "(Would install|already satisfied)"; then
        ok "pip3 可連 PyPI (Plan B 可行)"
        PIP_OK=true
    else
        warn "pip3 連不到 PyPI (公司內網可能擋外網)"
        PIP_OK=false
    fi
fi

# === 8. 結論 ===
echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║   建議方案                                                    ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

if echo "$FLASK_INFO" | grep -q "^Available\|^Installed"; then
    repo=$(echo "$FLASK_INFO" | grep -m1 "^From repo" | awk '{print $NF}')
    echo -e "${GREEN}→ Plan A: 直接 dnf install python3-flask (repo: $repo)${NC}"
    echo "  跑: curl -fsSL https://github.com/alienid4/cl_ftp/raw/main/release-zip/latest-fix-portal.sh | sudo bash"
elif [[ "$PIP_OK" == "true" ]]; then
    echo -e "${GREEN}→ Plan B: pip install (從 PyPI 抓 Flask)${NC}"
    echo "  Claude 會寫一支 fix_portal_pip.sh, 等等貼 URL"
elif echo "$MWS_INFO" | grep -q "^Available\|^Installed"; then
    echo -e "${YELLOW}→ Plan C: 改用 httpd + python3-mod_wsgi (純 AppStream)${NC}"
    echo "  Claude 會寫一支 fix_portal_modwsgi.sh, 改架構, 拋棄 nginx 反代 5000"
else
    echo -e "${RED}→ Plan D: 跟 IT 申請 enable CRB 或 EPEL${NC}"
    echo "  CRB 是免費內建 RHEL 訂閱, 不算違反「不用 EPEL」"
    echo "  跟 IT 說: subscription-manager repos --enable codeready-builder-for-rhel-9-x86_64-rpms"
fi

echo ""
echo "把本診斷輸出截圖貼給 Claude 決定下一步"
