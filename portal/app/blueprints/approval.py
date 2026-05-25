"""
Approval blueprint — 批次簽核 (ANY 制)
"""
import os
import shutil
from flask import Blueprint, render_template, request, redirect, url_for, flash, jsonify, abort
from flask_login import login_required, current_user
from ..db import (
    get_business_code, get_batch, get_batch_files,
    approve_batch, reject_batch, query, execute
)
from ..audit_helper import log_audit

approval_bp = Blueprint('approval', __name__, template_folder='../templates')


@approval_bp.route('/list')
@login_required
def list_view():
    """我的待簽 — 1 行 1 批"""
    from flask import current_app
    try:
        sql = """
        SELECT b.*, bc.name AS business_name, bc.approver_ad_group, bc.samba_dir
        FROM Batch b
        JOIN BusinessCode bc ON b.business_code = bc.code
        WHERE b.status = 'PENDING_APPROVAL'
        ORDER BY b.last_file_at DESC
        """
        batches = query(sql) or []
        # 過濾: 我必須是該業務的簽核 AD 群組成員
        my_batches = [
            b for b in batches
            if current_user.can_approve(b.get('approver_ad_group', ''))
        ]
    except Exception as e:
        current_app.logger.exception('[approval.list_view] 撈待簽失敗')
        flash(f'撈待簽失敗: {e}', 'error')
        my_batches = []
    return render_template('approval_list.html', batches=my_batches)


@approval_bp.route('/<batch_id>')
@login_required
def detail(batch_id):
    """簽核細節 — 顯示批次內所有檔, 可逐個勾選"""
    from flask import current_app
    try:
        batch = get_batch(batch_id)
        if not batch:
            flash('找不到此批次', 'error')
            return redirect(url_for('approval.list_view'))

        bc = get_business_code(batch.get('business_code'))
        if bc and not current_user.can_approve(bc.get('approver_ad_group', '')):
            try:
                log_audit('DENIED', actor_user=current_user.ad_account,
                          batch_id=batch_id, result='DENIED',
                          detail={'reason': 'not in approver group'})
            except Exception:
                pass
            abort(403)

        files = get_batch_files(batch_id) or []

        # v2.5: 算 deadline (first_file_at + retention_days)
        from datetime import timedelta
        deadline = None
        if batch.get('first_file_at') and bc:
            retention = bc.get('retention_days', 7)
            deadline = batch['first_file_at'] + timedelta(days=retention)

        # v2.5: 簽核群組成員 (階段二接 AD 真查, 現在 stub)
        approvers = _stub_approvers(bc.get('approver_ad_group') if bc else None)

    except Exception as e:
        current_app.logger.exception('[approval.detail] 撈失敗')
        flash(f'撈批次失敗: {e}', 'error')
        return redirect(url_for('approval.list_view'))
    return render_template('approval_detail.html',
                           batch=batch, bc=bc, files=files,
                           deadline=deadline, approvers=approvers)


def _stub_approvers(group_name):
    """階段一 stub: 給 5 個假名. 階段二接 AD 真查."""
    if not group_name:
        return []
    return [
        {'ad_account': 'CORP\\wang.manager', 'display_name': '王主管'},
        {'ad_account': 'CORP\\lin.deputy',   'display_name': '林副理'},
        {'ad_account': 'CORP\\huang.lead',   'display_name': '黃組長'},
        {'ad_account': 'CORP\\chou.audit',   'display_name': '周稽核'},
        {'ad_account': 'CORP\\wu.security',  'display_name': '吳資安'},
    ]


@approval_bp.route('/<batch_id>/approve', methods=['POST'])
@login_required
def do_approve(batch_id):
    """全收 / 細選同意 — ANY 制, 任 1 同意即放行"""
    # v2.5: confirm token 防護, 防止繞 UI 直接 POST
    if request.form.get('confirm') != 'yes':
        flash('簽核需經過預覽確認, 請從簽核細節頁按鈕操作', 'warn')
        return redirect(url_for('approval.detail', batch_id=batch_id))

    batch = get_batch(batch_id)
    bc = get_business_code(batch['business_code'])

    if not current_user.can_approve(bc['approver_ad_group']):
        abort(403)

    selected_files = request.form.getlist('selected_files')  # 細選用; 空 = 全收
    comment = request.form.get('comment', '')

    success = approve_batch(batch_id, current_user.ad_account)
    if not success:
        flash('此批次已被其他簽核人處理', 'warn')
        return redirect(url_for('approval.list_view'))

    # 搬檔 (簡化版, 真實要透過 svc_portal 服務)
    from flask import current_app
    samba_root = os.path.join(current_app.config['DATA_EXCHANGE_ROOT'], 'samba', bc['samba_dir'])
    os.makedirs(samba_root, exist_ok=True)

    files = get_batch_files(batch_id)
    moved_count = 0
    for f in files:
        if selected_files and str(f['id']) not in selected_files:
            # 細選未勾選 → 駁回單檔
            execute("UPDATE BatchFile SET decision='REJECTED', decision_by=?, decision_at=SYSUTCDATETIME() WHERE id=?",
                    (current_user.ad_account, f['id']))
            continue
        try:
            src = f['file_path']
            dst = os.path.join(samba_root, f['file_name'])
            shutil.move(src, dst)

            execute("""UPDATE BatchFile SET decision='APPROVED', decision_by=?, decision_at=SYSUTCDATETIME(),
                       final_path=?, moved_at=SYSUTCDATETIME() WHERE id=?""",
                    (current_user.ad_account, dst, f['id']))

            log_audit('MOVE_OK', source_system='PORTAL', actor_user=current_user.ad_account,
                      business_code=batch['business_code'], batch_id=batch_id,
                      target_file=f['file_name'], target_path=dst, file_size=f['file_size'])
            moved_count += 1
        except Exception as e:
            log_audit('MOVE_FAIL', actor_user=current_user.ad_account,
                      business_code=batch['business_code'], batch_id=batch_id,
                      target_file=f['file_name'], result='FAIL',
                      detail={'error': str(e)})

    log_audit('APPROVE_OK', actor_user=current_user.ad_account,
              business_code=batch['business_code'], batch_id=batch_id,
              detail={'moved': moved_count, 'total': len(files), 'comment': comment})

    flash(f'已同意, {moved_count}/{len(files)} 檔案放行到 samba', 'success')
    return redirect(url_for('approval.list_view'))


@approval_bp.route('/<batch_id>/reject', methods=['POST'])
@login_required
def do_reject(batch_id):
    """全退 — ANY 制, 任 1 駁回即駁回"""
    # v2.5: confirm token 防護
    if request.form.get('confirm') != 'yes':
        flash('駁回需經過預覽確認, 請從簽核細節頁按鈕操作', 'warn')
        return redirect(url_for('approval.detail', batch_id=batch_id))

    batch = get_batch(batch_id)
    bc = get_business_code(batch['business_code'])

    if not current_user.can_approve(bc['approver_ad_group']):
        abort(403)

    reason = request.form.get('reason', '').strip()
    if not reason:
        flash('駁回必須填寫原因', 'error')
        return redirect(url_for('approval.detail', batch_id=batch_id))

    success = reject_batch(batch_id, current_user.ad_account, reason)
    if not success:
        flash('此批次已被其他簽核人處理', 'warn')
        return redirect(url_for('approval.list_view'))

    log_audit('APPROVE_REJECT', actor_user=current_user.ad_account,
              business_code=batch['business_code'], batch_id=batch_id,
              detail={'reason': reason})

    flash('已駁回, 上傳人將收到通知信', 'info')
    return redirect(url_for('approval.list_view'))
