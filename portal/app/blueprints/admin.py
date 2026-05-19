"""
Admin blueprint — 業務代號管理 / 帳號管理 / 系統健康
"""
from flask import Blueprint, render_template, request, redirect, url_for, flash, abort
from flask_login import login_required, current_user
from ..db import get_business_codes, get_business_code, query, execute
from ..audit_helper import log_audit

admin_bp = Blueprint('admin', __name__, template_folder='../templates')


def admin_required():
    if not current_user.is_admin:
        log_audit('DENIED', actor_user=current_user.ad_account, result='DENIED',
                  detail={'reason': 'admin page'})
        abort(403)


@admin_bp.route('/biz')
@login_required
def biz_list():
    admin_required()
    codes = get_business_codes(active_only=False)
    return render_template('admin_biz_list.html', codes=codes)


@admin_bp.route('/biz/new', methods=['GET', 'POST'])
@login_required
def biz_new():
    admin_required()
    if request.method == 'POST':
        # 簡化版, 真實還要建本機帳號 / AD 群組 / NTFS ACL
        code = request.form['code'].strip()
        name = request.form['name'].strip()
        owner = request.form.get('owner_ad', '').strip()
        approver_group = request.form.get('approver_ad_group', '').strip()
        samba_dir = request.form.get('samba_dir', '').strip()
        download_group = request.form.get('download_ad_group', '').strip()
        protocols = request.form.get('allow_protocols', 'SFTP')
        retention = int(request.form.get('retention_days', '7'))
        description = request.form.get('description', '')

        execute("""
            INSERT INTO BusinessCode (code, name, owner_ad, approver_ad_group, samba_dir,
                                     download_ad_group, retention_days, allow_protocols, description,
                                     is_active, created_at, created_by)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1, SYSUTCDATETIME(), ?)
        """, (code, name, owner, approver_group, samba_dir,
              download_group, retention, protocols, description, current_user.ad_account))

        log_audit('ADMIN_BIZ_NEW', source_system='ADMIN', actor_user=current_user.ad_account,
                  business_code=code, detail={
                      'name': name, 'owner': owner, 'approver_group': approver_group,
                      'samba_dir': samba_dir, 'retention': retention
                  })

        flash(f'業務代號 {code} 已建立, 請通知 PAM 管理員納管', 'success')
        return redirect(url_for('admin.biz_list'))

    return render_template('admin_biz_new.html')


@admin_bp.route('/biz/<code>/edit', methods=['GET', 'POST'])
@login_required
def biz_edit(code):
    admin_required()
    bc = get_business_code(code)
    if not bc:
        abort(404)

    if request.method == 'POST':
        new_path = request.form.get('new_samba_dir', '').strip()
        # samba 路徑變更 (6 步驟二次確認) — 此處只更新 DB, 實際 OS 操作另有腳本
        if new_path and new_path != bc['samba_dir']:
            execute("""
                INSERT INTO SambaPathHistory (business_code, old_path, new_path, changed_by, notes)
                VALUES (?, ?, ?, ?, ?)
            """, (code, bc['samba_dir'], new_path, current_user.ad_account,
                  request.form.get('change_reason', '')))

            execute("""UPDATE BusinessCode SET samba_dir = ?, updated_at = SYSUTCDATETIME(),
                      updated_by = ? WHERE code = ?""",
                    (new_path, current_user.ad_account, code))

            log_audit('SAMBA_PATH_CHANGE', source_system='ADMIN', actor_user=current_user.ad_account,
                      business_code=code, detail={'old': bc['samba_dir'], 'new': new_path})

            flash(f'samba 路徑已變更: {bc["samba_dir"]} → {new_path}. 請通知 OA 端 USER 重掛新路徑', 'warn')

        # 其他基本欄位更新
        execute("""UPDATE BusinessCode SET name=?, owner_ad=?, description=?,
                  retention_days=?, updated_at=SYSUTCDATETIME(), updated_by=? WHERE code=?""",
                (request.form['name'], request.form.get('owner_ad', ''),
                 request.form.get('description', ''),
                 int(request.form.get('retention_days', '7')),
                 current_user.ad_account, code))

        log_audit('ADMIN_BIZ_EDIT', source_system='ADMIN', actor_user=current_user.ad_account,
                  business_code=code)

        return redirect(url_for('admin.biz_list'))

    path_history = query(
        "SELECT * FROM SambaPathHistory WHERE business_code = ? ORDER BY changed_at DESC",
        (code,)
    )
    return render_template('admin_biz_edit.html', bc=bc, path_history=path_history)


@admin_bp.route('/health')
@login_required
def health():
    """系統健康 (從 health_check.ps1 抓 JSON)"""
    admin_required()
    import subprocess
    import json
    try:
        result = subprocess.run(
            ['powershell.exe', '-File', r'C:\ClaudeHome\SFTP\scripts\health_check.ps1', '-Json'],
            capture_output=True, text=True, timeout=30
        )
        health_data = json.loads(result.stdout) if result.returncode == 0 else None
    except Exception as e:
        health_data = {'error': str(e)}
    return render_template('admin_health.html', health=health_data)
