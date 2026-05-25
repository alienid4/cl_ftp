"""
SF Portal — AD/LDAP 認證 + User Model
使用者用 AD 帳號登入, Portal 從 AD 查群組成員, 不存個人密碼。

支援兩種 bind mode (由 .env AD_AUTH_MODE 控制):
  - simple (default): 服務帳號查 user DN → 該 DN+密碼 bind 驗證 (相容 OpenLDAP/glauth/AD)
  - ntlm: 直接 NTLM bind (Windows AD 專用)

DEV_MODE=true 時跳過所有 AD, 任何帳密都接受 (僅供開發/demo).
"""
import os
from typing import Optional
from flask_login import UserMixin
from flask import current_app
from ldap3 import Server, Connection, ALL, NTLM, SIMPLE, SUBTREE
from .db import query_one, execute


class User(UserMixin):
    """Portal User Model — 對應 PortalUser 表 + AD 群組資訊"""
    def __init__(self, ad_account: str, display_name: str = None, email: str = None,
                 department: str = None, is_admin: bool = False, groups: list = None):
        self.id = ad_account
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


def _dev_mode():
    return os.getenv('DEV_MODE', '').lower() in ('1', 'true', 'yes')


def _auth_mode():
    return (os.getenv('AD_AUTH_MODE', 'simple') or 'simple').lower()


def load_user(ad_account: str) -> Optional[User]:
    """flask-login user_loader — 從 session 還原 User"""
    if _dev_mode():
        return User(
            ad_account=ad_account,
            display_name=ad_account + ' (DEV)',
            email='dev@example.local',
            department='DEV',
            is_admin=True,
            groups=['sf_admin', 'g_u01_approvers', 'g_u02_approvers', 'g_u03_approvers', 'g_u04_approvers'],
        )

    # 真實模式: 從 DB cache 取基本資料, 群組從 LDAP 即時查
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


# ===== LDAP helpers =====

def _service_bind():
    """用 svc_portal_ldap 服務帳號 bind, 用來查 user DN / groups"""
    cfg = current_app.config
    bind_user = cfg.get('AD_BIND_USER') or ''
    bind_pass = cfg.get('AD_BIND_PASS') or ''
    if not bind_user or not bind_pass:
        return None
    try:
        server = Server(cfg['AD_SERVER'], get_info=ALL)
        if _auth_mode() == 'ntlm':
            return Connection(server, user=bind_user, password=bind_pass,
                              authentication=NTLM, auto_bind=True)
        return Connection(server, user=bind_user, password=bind_pass,
                          authentication=SIMPLE, auto_bind=True)
    except Exception as e:
        current_app.logger.warning('[AD] service bind 失敗: ' + str(e))
        return None


def _find_user_dn(username):
    """用服務帳號查 user 的 LDAP DN + attrs (mail, displayName, memberOf, department)"""
    cfg = current_app.config
    conn = _service_bind()
    if not conn:
        return None
    try:
        # 兼容 glauth (cn) 跟 AD (sAMAccountName)
        flt = '(|(cn=' + username + ')(sAMAccountName=' + username + ')(uid=' + username + '))'
        conn.search(
            search_base=cfg['AD_BASE_DN'],
            search_filter=flt,
            search_scope=SUBTREE,
            attributes=['displayName', 'cn', 'sn', 'givenName', 'mail', 'department', 'memberOf']
        )
        if not conn.entries:
            return None
        e = conn.entries[0]
        return {
            'dn': str(e.entry_dn),
            'display_name': str(e.displayName) if e.displayName else (str(e.cn) if e.cn else username),
            'mail': str(e.mail) if e.mail else None,
            'department': str(e.department) if e.department else None,
            'member_of': list(e.memberOf) if e.memberOf else [],
        }
    except Exception as e:
        current_app.logger.warning('[AD] find_user_dn 失敗 ' + username + ': ' + str(e))
        return None
    finally:
        try:
            conn.unbind()
        except Exception:
            pass


def _groups_from_member_of(member_of_list):
    """從 memberOf DN list 抓出群組 CN"""
    groups = []
    for dn in member_of_list:
        for part in str(dn).split(','):
            if part.strip().lower().startswith('cn='):
                groups.append(part.strip()[3:])
                break
            if part.strip().lower().startswith('ou='):
                # glauth 用 ou=groupname
                groups.append(part.strip()[3:])
                break
    return groups


# ===== Public auth API =====

def authenticate(username: str, password: str):
    """
    驗證 username / password.
    回傳 (user_or_None, reason_str).
      reason 為 'OK' / 'EMPTY_FIELD' / 'AD_UNREACHABLE' / 'SERVICE_BIND_FAIL'
            / 'USER_NOT_FOUND' / 'BAD_PASSWORD' / 'EXCEPTION'
    """
    if not username or not password:
        return None, 'EMPTY_FIELD'

    if _dev_mode():
        current_app.logger.warning('[DEV_MODE] bypass AD: ' + username)
        return User(
            ad_account=username or 'devadmin',
            display_name=(username or 'devadmin') + ' (DEV)',
            email='dev@example.local',
            department='DEV',
            is_admin=True,
            groups=['sf_admin', 'g_u01_approvers', 'g_u02_approvers', 'g_u03_approvers', 'g_u04_approvers'],
        ), 'OK'

    user_part = username.split('\\')[-1] if '\\' in username else username

    if _auth_mode() == 'ntlm':
        return _auth_ntlm(user_part, password)
    return _auth_simple(user_part, password)


def _auth_simple(username, password):
    """LDAP simple bind 兩段式: 服務帳號查 DN → 該 DN+pwd 驗證"""
    cfg = current_app.config
    import socket as _sk
    # 1. AD server 連得到嗎?
    try:
        _sk.create_connection((cfg['AD_SERVER'].split('://')[-1].split(':')[0],
                              int(cfg['AD_SERVER'].rsplit(':', 1)[-1]) if ':' in cfg['AD_SERVER'].split('://')[-1] else 389),
                              timeout=3).close()
    except Exception as e:
        current_app.logger.warning('[AD-simple] server unreachable ' + cfg['AD_SERVER'] + ': ' + str(e))
        return None, 'AD_UNREACHABLE'

    # 2. 服務帳號 bind
    svc = _service_bind()
    if not svc:
        return None, 'SERVICE_BIND_FAIL'
    svc.unbind()

    # 3. 查 user DN
    info = _find_user_dn(username)
    if not info:
        current_app.logger.info('[AD-simple] user not found: ' + username)
        return None, 'USER_NOT_FOUND'

    # 4. user DN + password 真正 bind
    user_dn = info['dn']
    try:
        from ldap3 import Server, Connection, ALL, SIMPLE
        server = Server(cfg['AD_SERVER'], get_info=ALL)
        Connection(server, user=user_dn, password=password,
                   authentication=SIMPLE, auto_bind=True).unbind()
    except Exception as e:
        current_app.logger.info('[AD-simple] bad password for ' + user_dn + ': ' + str(e))
        return None, 'BAD_PASSWORD'

    groups = _groups_from_member_of(info['member_of'])
    is_admin = any('sf_admin' in g.lower() or 'it.admin' in g.lower() for g in groups)

    try:
        upsert_portal_user(username, info['display_name'], info['mail'], info['department'], is_admin)
    except Exception as e:
        current_app.logger.warning('[AD-simple] upsert PortalUser 失敗: ' + str(e))

    return User(
        ad_account=username,
        display_name=info['display_name'],
        email=info['mail'],
        department=info['department'],
        is_admin=is_admin,
        groups=groups,
    ), 'OK'


def _auth_ntlm(username, password):
    """NTLM bind (Windows AD)"""
    cfg = current_app.config
    domain = cfg['AD_DOMAIN']
    nt_user = domain + '\\' + username
    try:
        server = Server(cfg['AD_SERVER'], get_info=ALL)
        conn = Connection(server, user=nt_user, password=password,
                          authentication=NTLM, auto_bind=True)
        conn.search(
            search_base=cfg['AD_BASE_DN'],
            search_filter='(sAMAccountName=' + username + ')',
            search_scope=SUBTREE,
            attributes=['displayName', 'mail', 'department', 'memberOf']
        )
        if not conn.entries:
            conn.unbind()
            return None, 'USER_NOT_FOUND'
        e = conn.entries[0]
        display_name = str(e.displayName) if e.displayName else username
        email = str(e.mail) if e.mail else None
        department = str(e.department) if e.department else None
        groups = _groups_from_member_of(list(e.memberOf) if e.memberOf else [])
        is_admin = any('sf_admin' in g.lower() or 'it.admin' in g.lower() for g in groups)
        conn.unbind()
        try:
            upsert_portal_user(nt_user, display_name, email, department, is_admin)
        except Exception:
            pass
        return User(
            ad_account=nt_user,
            display_name=display_name,
            email=email,
            department=department,
            is_admin=is_admin,
            groups=groups,
        ), 'OK'
    except Exception as e:
        msg = str(e).lower()
        current_app.logger.warning('[AD-ntlm] bind 失敗 ' + nt_user + ': ' + str(e))
        if 'invalidcredentials' in msg or 'invalid credentials' in msg:
            return None, 'BAD_PASSWORD'
        if 'cant contact' in msg or "can't contact" in msg or 'unreachable' in msg:
            return None, 'AD_UNREACHABLE'
        return None, 'EXCEPTION'


def get_user_groups(ad_account):
    """查 user 的群組 (給 load_user 用, 從 session 還原時呼叫)"""
    if _dev_mode():
        return []
    user_part = ad_account.split('\\')[-1] if '\\' in ad_account else ad_account
    info = _find_user_dn(user_part)
    if not info:
        return []
    return _groups_from_member_of(info['member_of'])


def get_group_members(group_name):
    """
    查群組成員 (CN + mail). 給寄信用.
    回傳 list of dict: [{ad_account, display_name, mail}, ...]
    """
    if _dev_mode():
        return []
    cfg = current_app.config
    conn = _service_bind()
    if not conn:
        return []
    try:
        # glauth: user.ou=<group>; AD: memberOf=<group_dn>
        # 簡化: 全 search 找 memberOf 含 group_name
        conn.search(
            search_base=cfg['AD_BASE_DN'],
            search_filter='(memberOf=*' + group_name + '*)',
            search_scope=SUBTREE,
            attributes=['cn', 'displayName', 'mail', 'sAMAccountName']
        )
        members = []
        for e in conn.entries:
            ad_account = str(e.cn) if e.cn else (str(e.sAMAccountName) if e.sAMAccountName else None)
            if not ad_account:
                continue
            members.append({
                'ad_account': ad_account,
                'display_name': str(e.displayName) if e.displayName else ad_account,
                'mail': str(e.mail) if e.mail else None,
            })
        return members
    except Exception as e:
        current_app.logger.warning('[AD] get_group_members 失敗 ' + group_name + ': ' + str(e))
        return []
    finally:
        try:
            conn.unbind()
        except Exception:
            pass


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
