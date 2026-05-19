"""
API blueprint — JSON endpoints (給內部監控用)
"""
from datetime import datetime
from flask import Blueprint, jsonify
from flask_login import login_required, current_user
from ..db import query

api_bp = Blueprint('api', __name__)


@api_bp.route('/health')
def health():
    """無需登入的健康檢查 endpoint (給 monitoring 系統用)"""
    try:
        # DB 連線測試
        row = query("SELECT 1 AS ok", ())[0]
        db_ok = row['ok'] == 1
    except Exception:
        db_ok = False

    status = {
        'service': 'sf-portal',
        'status': 'ok' if db_ok else 'degraded',
        'db': 'ok' if db_ok else 'fail',
        'timestamp': datetime.utcnow().isoformat() + 'Z',
    }
    return jsonify(status), 200 if db_ok else 503


@api_bp.route('/me')
@login_required
def me():
    """當前登入者資訊"""
    return jsonify({
        'ad_account': current_user.ad_account,
        'display_name': current_user.display_name,
        'department': current_user.department,
        'is_admin': current_user.is_admin,
        'groups': current_user.groups,
    })
