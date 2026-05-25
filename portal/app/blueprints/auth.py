"""
Auth blueprint — Login / Logout
"""
from flask import Blueprint, render_template, request, redirect, url_for, flash
from flask_login import login_user, logout_user, login_required, current_user
from ..auth import authenticate
from ..audit_helper import log_audit

auth_bp = Blueprint('auth', __name__, template_folder='../templates')


FAIL_MSG = {
    'EMPTY_FIELD':       '帳號或密碼空白, 請填寫',
    'AD_UNREACHABLE':    'AD/LDAP server 連不到 (檢查 AD_SERVER 設定 + sf-mock-ad 服務)',
    'SERVICE_BIND_FAIL': '服務帳號 bind 失敗 (檢查 .env 內 AD_BIND_USER/AD_BIND_PASS)',
    'USER_NOT_FOUND':    '帳號不存在於 AD/LDAP',
    'BAD_PASSWORD':      '密碼錯誤',
    'EXCEPTION':         '登入過程異常, 請查 portal-stderr.log',
}


@auth_bp.route('/login', methods=['GET', 'POST'])
def login():
    if current_user.is_authenticated:
        return redirect(url_for('main.home'))

    if request.method == 'POST':
        username = request.form.get('username', '').strip()
        password = request.form.get('password', '')

        user, reason = authenticate(username, password)
        if user:
            login_user(user, remember=False)
            log_audit('LOGIN_OK', actor_user=user.ad_account)
            return redirect(url_for('main.home'))

        log_audit('LOGIN_FAIL', actor_user=username, result='FAIL',
                  detail={'reason': reason})
        msg = FAIL_MSG.get(reason, '登入失敗 (' + reason + ')')
        # 安全考量: 正式環境只顯通用訊息. LAB / .env 設 SHOW_LOGIN_FAIL_REASON=true 顯具體
        import os as _os
        if _os.getenv('SHOW_LOGIN_FAIL_REASON', 'true').lower() in ('1', 'true', 'yes'):
            flash(msg, 'error')
        else:
            flash('帳號或密碼錯誤', 'error')

    return render_template('login.html')


@auth_bp.route('/logout')
@login_required
def logout():
    user_id = current_user.id
    logout_user()
    log_audit('LOGIN_OK', actor_user=user_id, result='LOGOUT')
    flash('已登出', 'info')
    return redirect(url_for('auth.login'))
