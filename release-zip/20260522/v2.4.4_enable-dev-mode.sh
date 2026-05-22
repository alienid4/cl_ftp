#!/bin/bash
#
# v2.4.4_enable-dev-mode.sh — SF Portal 啟用 DEV_MODE (跳過 AD bind)
#
# 情境: USER 沒設好公司 AD bind, 想先用任何帳密進 portal 看各頁能不能跑.
#
# 動作:
#   1. 蓋寫 /opt/portal/app/app/auth.py (加 DEV_MODE bypass)
#   2. 加 DEV_MODE=true 到 /opt/portal/app/.env (有就改, 沒就加)
#   3. py_compile 驗 auth.py
#   4. systemctl restart sf-portal
#   5. curl 驗 portal 起來
#
# 之後關掉 dev mode: 把 .env 內 DEV_MODE=true 改成 false, restart sf-portal
#
# 用法:
#   sudo bash /tmp/ftp-lab/v2.4.4_enable-dev-mode.sh

set -uo pipefail

CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
step() { echo ""; echo -e "${CYAN}=== $* ===${NC}"; }
ok()   { echo -e "${GREEN}[ok]${NC} $*"; }
warn() { echo -e "${YELLOW}[warn]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }

[[ $EUID -eq 0 ]] || fail "請 sudo 跑"

PORTAL_DIR=/opt/portal
AUTH_PY=$PORTAL_DIR/app/app/auth.py
ENV_FILE=$PORTAL_DIR/app/.env

[[ -f "$AUTH_PY" ]] || fail "$AUTH_PY 不存在 — Portal 還沒裝?"
[[ -f "$ENV_FILE" ]] || fail "$ENV_FILE 不存在 — Portal 還沒裝?"

step "Step 1: backup 舊 auth.py"
cp "$AUTH_PY" "${AUTH_PY}.bak.$(date +%s)"
ok "已備份"

step "Step 2: 蓋寫 auth.py (加 DEV_MODE bypass)"

cat > "$AUTH_PY" <<'PYEOF'
"""
SF Portal — AD/LDAP 認證 + User Model
使用者用 AD 帳號登入, Portal 從 AD 查群組成員, 不存個人密碼。
"""
from typing import Optional
from flask_login import UserMixin
from flask import current_app
from ldap3 import Server, Connection, ALL, NTLM, SUBTREE
from .db import query_one, execute


class User(UserMixin):
    """Portal User Model — 對應 PortalUser 表 + AD 群組資訊"""
    def __init__(self, ad_account: str, display_name: str = None, email: str = None,
                 department: str = None, is_admin: bool = False, groups: list = None):
        self.id = ad_account               # flask-login 用 .id
        self.ad_account = ad_account
        self.display_name = display_name or ad_account
        self.email = email
        self.department = department
        self.is_admin = is_admin
        self.groups = groups or []

    def is_in_group(self, group_name: str) -> bool:
        return any(group_name.lower() in g.lower() for g in self.groups)

    def can_approve(self, approver_group: str) -> bool:
        return self.is_in_group(approver_group)

    def can_download(self, download_group: str) -> bool:
        return self.is_in_group(download_group)


def load_user(ad_account: str) -> Optional[User]:
    """flask-login 的 user_loader — 從 session 還原 User"""
    import os
    if os.getenv('DEV_MODE', '').lower() in ('1', 'true', 'yes'):
        return User(
            ad_account=ad_account,
            display_name=ad_account + ' (DEV)',
            email='dev@example.local',
            department='DEV',
            is_admin=True,
            groups=['sf_admin', 'g_u01_approvers', 'g_u02_approvers', 'g_u03_approvers', 'g_u04_approvers'],
        )

    rec = query_one(
        "SELECT * FROM PortalUser WHERE ad_account = ? AND is_active = 1",
        (ad_account,)
    )
    if not rec:
        return None

    groups = get_user_groups(ad_account)
    return User(
        ad_account=rec['ad_account'],
        display_name=rec.get('display_name'),
        email=rec.get('email'),
        department=rec.get('department'),
        is_admin=bool(rec.get('is_admin')),
        groups=groups,
    )


def authenticate(username: str, password: str) -> Optional[User]:
    """
    對 AD 進行 LDAP bind 驗證。
    DEV_MODE=true 時跳過 AD, 任何帳密都接受, 預設 admin 身分。
    """
    cfg = current_app.config

    import os
    if os.getenv('DEV_MODE', '').lower() in ('1', 'true', 'yes'):
        current_app.logger.warning('[DEV_MODE] bypass AD, 接受 ' + (username or '') + ' 為 admin')
        return User(
            ad_account=username or 'devadmin',
            display_name=(username or 'devadmin') + ' (DEV)',
            email='dev@example.local',
            department='DEV',
            is_admin=True,
            groups=['sf_admin', 'g_u01_approvers', 'g_u02_approvers', 'g_u03_approvers', 'g_u04_approvers'],
        )

    domain = cfg['AD_DOMAIN']

    if '\\' in username:
        domain_part, user_part = username.split('\\', 1)
    else:
        user_part = username
        domain_part = domain

    upn = user_part + '@' + domain_part.lower() + '.local'
    nt_user = domain_part + '\\' + user_part

    try:
        server = Server(cfg['AD_SERVER'], get_info=ALL)
        conn = Connection(server, user=nt_user, password=password, authentication=NTLM, auto_bind=True)

        base = cfg['AD_BASE_DN']
        conn.search(
            search_base=base,
            search_filter='(sAMAccountName=' + user_part + ')',
            search_scope=SUBTREE,
            attributes=['displayName', 'mail', 'department', 'memberOf']
        )

        if not conn.entries:
            return None

        entry = conn.entries[0]
        display_name = str(entry.displayName) if entry.displayName else user_part
        email = str(entry.mail) if entry.mail else None
        department = str(entry.department) if entry.department else None
        member_of = list(entry.memberOf) if entry.memberOf else []

        groups = []
        for dn in member_of:
            for part in dn.split(','):
                if part.upper().startswith('CN='):
                    groups.append(part[3:])
                    break

        is_admin = any('sf_admin' in g.lower() or 'it.admin' in g.lower() for g in groups)

        conn.unbind()
        upsert_portal_user(nt_user, display_name, email, department, is_admin)

        return User(
            ad_account=nt_user,
            display_name=display_name,
            email=email,
            department=department,
            is_admin=is_admin,
            groups=groups,
        )

    except Exception as e:
        current_app.logger.warning('[AUTH] AD bind 失敗: ' + nt_user + ' / ' + str(e))
        return None


def upsert_portal_user(ad_account, display_name, email, department, is_admin):
    existing = query_one("SELECT * FROM PortalUser WHERE ad_account = ?", (ad_account,))
    if existing:
        execute("""
            UPDATE PortalUser SET display_name = ?, email = ?, department = ?,
                                  is_admin = ?, last_login_at = SYSUTCDATETIME(),
                                  login_count = login_count + 1
            WHERE ad_account = ?
        """, (display_name, email, department, 1 if is_admin else 0, ad_account))
    else:
        execute("""
            INSERT INTO PortalUser (ad_account, display_name, email, department, is_admin,
                                    first_login_at, last_login_at, login_count, is_active)
            VALUES (?, ?, ?, ?, ?, SYSUTCDATETIME(), SYSUTCDATETIME(), 1, 1)
        """, (ad_account, display_name, email, department, 1 if is_admin else 0))


def get_user_groups(ad_account: str) -> list:
    cfg = current_app.config
    if not cfg.get('AD_BIND_USER') or not cfg.get('AD_BIND_PASS'):
        return []

    try:
        user_part = ad_account.split('\\')[-1] if '\\' in ad_account else ad_account

        server = Server(cfg['AD_SERVER'], get_info=ALL)
        conn = Connection(server, user=cfg['AD_BIND_USER'], password=cfg['AD_BIND_PASS'],
                          authentication=NTLM, auto_bind=True)

        conn.search(
            search_base=cfg['AD_BASE_DN'],
            search_filter='(sAMAccountName=' + user_part + ')',
            attributes=['memberOf']
        )

        if not conn.entries:
            return []

        member_of = list(conn.entries[0].memberOf) if conn.entries[0].memberOf else []
        groups = []
        for dn in member_of:
            for part in dn.split(','):
                if part.upper().startswith('CN='):
                    groups.append(part[3:])
                    break

        conn.unbind()
        return groups

    except Exception as e:
        current_app.logger.warning('[AD] 查群組失敗 ' + ad_account + ': ' + str(e))
        return []
PYEOF

ok "auth.py 已蓋寫"

step "Step 3: py_compile 驗 auth.py 語法"
if /usr/bin/python3 -m py_compile "$AUTH_PY" 2>&1; then
    ok "auth.py 語法 OK"
else
    fail "auth.py py_compile 失敗"
fi

step "Step 4: 加 DEV_MODE=true 到 .env"
if grep -q '^DEV_MODE=' "$ENV_FILE"; then
    sed -i 's|^DEV_MODE=.*|DEV_MODE=true|' "$ENV_FILE"
    ok ".env 內 DEV_MODE 已更新為 true"
else
    echo "" >> "$ENV_FILE"
    echo "# v2.4.4 加 — DEV_MODE bypass AD bind, 上線前改 false" >> "$ENV_FILE"
    echo "DEV_MODE=true" >> "$ENV_FILE"
    ok "DEV_MODE=true 已加到 .env"
fi

step "Step 5: 修權限"
RUN_USER="nginx"
id -u nginx &>/dev/null || RUN_USER="portal"
chown "$RUN_USER:$RUN_USER" "$AUTH_PY" "$ENV_FILE" 2>/dev/null || true

step "Step 6: 重啟 sf-portal"
systemctl restart sf-portal
sleep 3
if systemctl is-active sf-portal &>/dev/null; then
    ok "sf-portal active"
else
    fail "sf-portal 啟動失敗, 看 journalctl -u sf-portal -n 30 --no-pager"
fi

step "Step 7: 驗證 HTTP"
code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 http://127.0.0.1:5000/ 2>/dev/null || echo 000)
echo "gunicorn 直連: HTTP $code"
code2=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 http://127.0.0.1/ 2>/dev/null || echo 000)
echo "nginx 反代:    HTTP $code2"

MAIN_IP=$(ip -4 addr | grep -E 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}' | cut -d/ -f1)

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   ✅ DEV_MODE 啟用完成                                        ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  瀏覽器開: http://$MAIN_IP/"
echo ""
echo "  登入頁輸入:"
echo "    AD 帳號 = (隨便, 例: admin / 01003385 / abc)"
echo "    密碼    = (隨便, 例: 123)"
echo ""
echo "  進去後身分: admin (可看管理員介面)"
echo ""
echo "  ⚠️  上線前改 /opt/portal/app/.env 內 DEV_MODE=false, 然後 systemctl restart sf-portal"
