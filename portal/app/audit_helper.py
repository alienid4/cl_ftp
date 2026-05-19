"""
SF Portal — AuditLog Helper
所有業務事件透過這支寫入, 不直接在 blueprints 寫 SQL。
"""
import json
import socket
from datetime import datetime, timezone
from flask import current_app, request
from .db import execute


# 事件類型對應 CEF Signature / Severity (預留接 SIEM)
EVENT_CEF_MAPPING = {
    'LOGIN_OK':         ('SF-100', 3),
    'LOGIN_FAIL':       ('SF-101', 5),
    'LOGIN_LOCKED':     ('SF-102', 7),
    'SFTP_UPLOAD':      ('SF-200', 3),
    'FTPS_UPLOAD':      ('SF-201', 3),
    'BATCH_PENDING':    ('SF-210', 3),
    'APPROVE_OK':       ('SF-300', 4),
    'APPROVE_REJECT':   ('SF-301', 4),
    'APPROVE_TIMEOUT':  ('SF-302', 4),
    'MOVE_OK':          ('SF-400', 3),
    'MOVE_FAIL':        ('SF-401', 6),
    'SMB_DOWNLOAD':     ('SF-500', 3),
    'PORTAL_DOWNLOAD':  ('SF-501', 3),
    'PORTAL_ZIP':       ('SF-502', 3),
    'DENIED':           ('SF-900', 7),
    'AUDIT_QUERY':      ('SF-700', 4),
    'AUDIT_EXPORT':     ('SF-701', 5),
    'ADMIN_BIZ_NEW':    ('SF-800', 5),
    'ADMIN_BIZ_EDIT':   ('SF-801', 5),
    'ADMIN_BIZ_DEL':    ('SF-802', 7),
    'SAMBA_PATH_CHANGE': ('SF-810', 7),
    'GROUP_ADD':        ('SF-820', 5),
    'GROUP_REMOVE':     ('SF-821', 5),
}


def log_audit(
    event_type: str,
    source_system: str = 'PORTAL',
    actor_user: str = None,
    business_code: str = None,
    batch_id: str = None,
    target_file: str = None,
    target_path: str = None,
    file_size: int = None,
    file_hash: str = None,
    result: str = 'SUCCESS',
    detail: dict = None,
    chain_id: str = None,
    pam_request_id: str = None,
):
    """
    寫一筆 AuditLog。
    所有業務操作都應呼叫這支。
    """
    cef_sig, cef_sev = EVENT_CEF_MAPPING.get(event_type, ('SF-000', 3))

    # 從 Flask request 自動補 IP
    source_ip = None
    try:
        if request:
            source_ip = request.headers.get('X-Real-IP') or request.remote_addr
    except RuntimeError:
        # 不在 request context 內 (例如排程觸發)
        pass

    detail_json = json.dumps(detail, ensure_ascii=False) if detail else None

    sql = """
    INSERT INTO AuditLog (
        event_time, event_type, source_system, actor_user, source_ip,
        business_code, batch_id, target_path, target_file,
        file_size, file_hash, result, detail,
        chain_id, pam_request_id,
        cef_signature, cef_severity, syslog_facility
    ) VALUES (
        SYSUTCDATETIME(), ?, ?, ?, ?,
        ?, ?, ?, ?,
        ?, ?, ?, ?,
        ?, ?,
        ?, ?, 'local0'
    )
    """

    params = (
        event_type, source_system, actor_user, source_ip,
        business_code, batch_id, target_path, target_file,
        file_size, file_hash, result, detail_json,
        chain_id, pam_request_id,
        cef_sig, cef_sev
    )

    try:
        execute(sql, params)
        current_app.logger.info(f'[AUDIT] {event_type} actor={actor_user} biz={business_code} result={result}')
    except Exception as e:
        current_app.logger.error(f'[AUDIT-FAIL] {event_type} 寫入失敗: {e}')


def search_audit(
    actor: str = None,
    business_code: str = None,
    file_pattern: str = None,
    source_ip: str = None,
    event_type: str = None,
    since: datetime = None,
    until: datetime = None,
    limit: int = 200,
) -> list[dict]:
    """稽核查詢 (給 admin 查詢頁用)"""
    from .db import query
    where = ['1=1']
    params = []

    if actor:
        where.append("actor_user LIKE ?")
        params.append(f'%{actor}%')
    if business_code:
        where.append("business_code = ?")
        params.append(business_code)
    if file_pattern:
        where.append("target_file LIKE ?")
        params.append(file_pattern.replace('*', '%'))
    if source_ip:
        where.append("source_ip = ?")
        params.append(source_ip)
    if event_type:
        where.append("event_type = ?")
        params.append(event_type)
    if since:
        where.append("event_time >= ?")
        params.append(since)
    if until:
        where.append("event_time <= ?")
        params.append(until)

    sql = f"""
    SELECT TOP {limit} *
    FROM V_AuditLog_Detail
    WHERE {' AND '.join(where)}
    ORDER BY event_time DESC
    """
    return query(sql, tuple(params))
