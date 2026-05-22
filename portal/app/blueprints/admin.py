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
    try:
        codes = get_business_codes(active_only=False)
    except Exception as e:
        from flask import current_app
        current_app.logger.exception('[ADMIN] biz_list 撈業務代號失敗')
        flash(f'撈業務代號失敗: {e}', 'error')
        codes = []
    return render_template('admin_biz_list.html', codes=codes or [])


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
    from flask import current_app
    admin_required()
    try:
        bc = get_business_code(code)
    except Exception as e:
        current_app.logger.exception('[ADMIN] biz_edit get_business_code 失敗')
        flash(f'撈業務代號失敗: {e}', 'error')
        return redirect(url_for('admin.biz_list'))

    if not bc:
        flash(f'找不到業務代號 {code}', 'error')
        return redirect(url_for('admin.biz_list'))

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

    try:
        path_history = query(
            "SELECT * FROM SambaPathHistory WHERE business_code = ? ORDER BY changed_at DESC",
            (code,)
        ) or []
    except Exception:
        path_history = []
    return render_template('admin_biz_edit.html', bc=bc, path_history=path_history)


@admin_bp.route('/health')
@login_required
def health():
    """系統健康 — Linux 版, 用 systemctl + /proc + psql 撈"""
    admin_required()
    import subprocess
    import shutil

    services = []
    for svc in ('sf-portal', 'nginx', 'postgresql', 'firewalld'):
        try:
            r = subprocess.run(['systemctl', 'is-active', svc],
                               capture_output=True, text=True, timeout=3)
            status_text = r.stdout.strip()
            status = 'OK' if status_text == 'active' else 'FAIL'
            services.append({'name': svc, 'status': status, 'detail': status_text})
        except Exception as e:
            services.append({'name': svc, 'status': 'FAIL', 'detail': str(e)})

    # 主機資源 (從 /proc)
    cpu_pct = mem_pct = disk_pct = None
    uptime = None
    try:
        with open('/proc/loadavg') as f:
            load1 = float(f.read().split()[0])
        # 粗估 cpu_pct 用 load1 / cpu_count
        import os as _os
        cpu_count = _os.cpu_count() or 1
        cpu_pct = min(int(load1 / cpu_count * 100), 100)
    except Exception:
        pass

    try:
        with open('/proc/meminfo') as f:
            mem = {}
            for line in f:
                k, v = line.split(':', 1)
                mem[k] = int(v.strip().split()[0])
        total = mem.get('MemTotal', 0)
        avail = mem.get('MemAvailable', 0)
        if total > 0:
            mem_pct = int((total - avail) / total * 100)
    except Exception:
        pass

    try:
        s = shutil.disk_usage('/')
        disk_pct = int(s.used / s.total * 100)
    except Exception:
        pass

    try:
        with open('/proc/uptime') as f:
            secs = float(f.read().split()[0])
        days = int(secs // 86400)
        hours = int((secs % 86400) // 3600)
        uptime = f'{days}d {hours}h'
    except Exception:
        pass

    # DB 統計
    audit_count = biz_count = batch_count = None
    error = None
    try:
        from ..db import query_one
        r = query_one("SELECT count(*) AS c FROM AuditLog")
        audit_count = r['c'] if r else 0
        r = query_one("SELECT count(*) AS c FROM BusinessCode")
        biz_count = r['c'] if r else 0
        r = query_one("SELECT count(*) AS c FROM Batch")
        batch_count = r['c'] if r else 0
    except Exception as e:
        error = f'DB 查詢失敗: {e}'

    return render_template('admin_health.html',
                           services=services,
                           cpu_pct=cpu_pct, mem_pct=mem_pct, disk_pct=disk_pct,
                           uptime=uptime,
                           audit_count=audit_count, biz_count=biz_count, batch_count=batch_count,
                           error=error)
