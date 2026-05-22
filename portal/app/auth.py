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
        """是否能簽核某業務 (依 AD 群組)"""
        return self.is_in_group(approver_group)

    def can_download(self, download_group: str) -> bool:
        return self.is_in_group(download_group)


def load_user(ad_account: str) -> Optional[User]:
    """flask-login 的 user_loader — 從 session 還原 User"""
    rec = query_one(
        "SELECT * FROM PortalUser WHERE ad_account = ? AND is_active = 1",
        (ad_account,)
    )
    if not rec:
        return None

    # 從 AD 再查群組 (cache 至 session 比較好, 此處每次查 demo 用)
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
    username 可以是 'CORP\\xxx' 或 'xxx' (自動補 domain)。
    """
    cfg = current_app.config
    domain = cfg['AD_DOMAIN']

    # 標準化使用者名
    if '\\' in username:
        domain_part, user_part = username.split('\\', 1)
    else:
        user_part = username
        domain_part = domain

    upn = f'{user_part}@{domain_part.lower()}.local'
    nt_user = f'{domain_part}\\{user_part}'

    try:
        server = Server(cfg['AD_SERVER'], get_info=ALL)
        conn = Connection(server, user=nt_user, password=password, authentication=NTLM, auto_bind=True)

        # 查使用者 attributes
        base = cfg['AD_BASE_DN']
        conn.search(
            search_base=base,
            search_filter=f'(sAMAccountName={user_part})',
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

        # 從 DN 抓 CN (群組名)
        groups = []
        for dn in member_of:
            for part in dn.split(','):
                if part.upper().startswith('CN='):
                    groups.append(part[3:])
                    break

        is_admin = any('sf_admin' in g.lower() or 'it.admin' in g.lower() for g in groups)

        conn.unbind()

        # 更新 PortalUser cache
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
        current_app.logger.warning(f'[AUTH] AD bind 失敗: {nt_user} / {e}')
        return None


def upsert_portal_user(ad_account, display_name, email, department, is_admin):
    """更新 cache (登入時)"""
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


def get_user_groups(ad_account: str) -> list[str]:
    """查 AD 取得使用者所屬群組 (用服務帳號 bind, 不需個人密碼)"""
    cfg = current_app.config
    if not cfg.get('AD_BIND_USER') or not cfg.get('AD_BIND_PASS'):
        # 開發階段沒有 AD bind, 回 mock
        return []

    try:
        # 標準化
        user_part = ad_account.split('\\')[-1] if '\\' in ad_account else ad_account

        server = Server(cfg['AD_SERVER'], get_info=ALL)
        conn = Connection(server, user=cfg['AD_BIND_USER'], password=cfg['AD_BIND_PASS'],
                          authentication=NTLM, auto_bind=True)

        conn.search(
            search_base=cfg['AD_BASE_DN'],
            search_filter=f'(sAMAccountName={user_part})',
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
        current_app.logger.warning(f'[AD] 查群組失敗 {ad_account}: {e}')
        return []
