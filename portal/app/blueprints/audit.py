"""
Audit blueprint — 稽核查詢 (admin only)
"""
import io
import csv
from datetime import datetime, timedelta
from flask import Blueprint, render_template, request, abort, Response
from flask_login import login_required, current_user
from ..audit_helper import search_audit, log_audit

audit_bp = Blueprint('audit', __name__, template_folder='../templates')


def admin_required():
    if not current_user.is_admin:
        log_audit('DENIED', actor_user=current_user.ad_account, result='DENIED',
                  detail={'reason': 'audit page requires admin'})
        abort(403)


@audit_bp.route('/query')
@login_required
def query_view():
    admin_required()

    # 查詢條件
    actor = request.args.get('actor', '').strip() or None
    biz = request.args.get('business_code', '').strip() or None
    file_pat = request.args.get('file', '').strip() or None
    ip = request.args.get('ip', '').strip() or None
    et = request.args.get('event_type', '').strip() or None
    hours = int(request.args.get('hours', '24'))

    since = datetime.utcnow() - timedelta(hours=hours)
    results = search_audit(
        actor=actor, business_code=biz, file_pattern=file_pat,
        source_ip=ip, event_type=et, since=since, limit=500
    )

    log_audit('AUDIT_QUERY', source_system='ADMIN', actor_user=current_user.ad_account,
              detail={'conditions': dict(request.args)})

    return render_template('audit_query.html', results=results, query=request.args)


@audit_bp.route('/export')
@login_required
def export_csv():
    """匯出 CSV"""
    admin_required()

    actor = request.args.get('actor', '').strip() or None
    biz = request.args.get('business_code', '').strip() or None
    hours = int(request.args.get('hours', '24'))
    since = datetime.utcnow() - timedelta(hours=hours)

    results = search_audit(actor=actor, business_code=biz, since=since, limit=10000)

    output = io.StringIO()
    if results:
        writer = csv.DictWriter(output, fieldnames=results[0].keys())
        writer.writeheader()
        writer.writerows(results)

    log_audit('AUDIT_EXPORT', source_system='ADMIN', actor_user=current_user.ad_account,
              detail={'row_count': len(results)})

    return Response(
        output.getvalue(),
        mimetype='text/csv',
        headers={'Content-Disposition': f'attachment; filename=audit_{datetime.utcnow().strftime("%Y%m%d_%H%M%S")}.csv'}
    )
