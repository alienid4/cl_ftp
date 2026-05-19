"""
Auth blueprint — Login / Logout
"""
from flask import Blueprint, render_template, request, redirect, url_for, flash
from flask_login import login_user, logout_user, login_required, current_user
from ..auth import authenticate
from ..audit_helper import log_audit

auth_bp = Blueprint('auth', __name__, template_folder='../templates')


@auth_bp.route('/login', methods=['GET', 'POST'])
def login():
    if current_user.is_authenticated:
        return redirect(url_for('main.home'))

    if request.method == 'POST':
        username = request.form.get('username', '').strip()
        password = request.form.get('password', '')

        user = authenticate(username, password)
        if user:
            login_user(user, remember=False)
            log_audit('LOGIN_OK', actor_user=user.ad_account)
            return redirect(url_for('main.home'))
        else:
            log_audit('LOGIN_FAIL', actor_user=username, result='FAIL')
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
