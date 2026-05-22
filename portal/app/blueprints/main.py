"""
Main blueprint — 首頁 / Dashboard
"""
from flask import Blueprint, render_template
from flask_login import login_required, current_user
from ..db import get_user_pending_batches, get_business_codes, query_one

main_bp = Blueprint('main', __name__, template_folder='../templates')


@main_bp.route('/')
@login_required
def home():
    """首頁: KPI + 待簽核 + 我負責的業務"""
    # 容錯撈 (任何 DB 錯都先吞掉, 不要整頁 500)
    def _safe(fn, default=None):
        try:
            return fn()
        except Exception:
            return default

    pending_batches = _safe(lambda: get_user_pending_batches(current_user.ad_account), [])
    owned_codes = _safe(lambda: [bc for bc in (get_business_codes() or []) if bc.get('owner_ad') == current_user.ad_account], [])

    # admin Dashboard 用的 KPI
    biz_count = _safe(lambda: (query_one("SELECT count(*) AS c FROM BusinessCode WHERE is_active = 1") or {}).get('c', 0), 0)
    pending_count = _safe(lambda: (query_one("SELECT count(*) AS c FROM Batch WHERE status = 'PENDING_APPROVAL'") or {}).get('c', 0), 0)
    today_upload = _safe(lambda: (query_one("SELECT count(*) AS c FROM AuditLog WHERE event_type LIKE '%UPLOAD%' AND event_time::date = (NOW() AT TIME ZONE 'UTC')::date") or {}).get('c', 0), 0)
    today_denied = _safe(lambda: (query_one("SELECT count(*) AS c FROM AuditLog WHERE result = 'DENIED' AND event_time::date = (NOW() AT TIME ZONE 'UTC')::date") or {}).get('c', 0), 0)
    month_approved = _safe(lambda: (query_one("SELECT count(*) AS c FROM AuditLog WHERE event_type LIKE 'APPROVE%' AND event_time >= date_trunc('month', NOW() AT TIME ZONE 'UTC')") or {}).get('c', 0), 0)
    month_downloads = _safe(lambda: (query_one("SELECT count(*) AS c FROM AuditLog WHERE event_type LIKE '%DOWNLOAD%' AND event_time >= date_trunc('month', NOW() AT TIME ZONE 'UTC')") or {}).get('c', 0), 0)

    return render_template(
        'home.html',
        pending_batches=pending_batches,
        owned_codes=owned_codes,
        biz_count=biz_count,
        pending_count=pending_count,
        today_upload=today_upload,
        today_denied=today_denied,
        month_approved=month_approved,
        month_downloads=month_downloads,
        month_rejected=0,
        my_groups=current_user.groups if hasattr(current_user, 'groups') else [],
    )
