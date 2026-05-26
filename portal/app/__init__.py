"""
SF Portal Flask Application Factory
"""
import os
import logging
from logging.handlers import RotatingFileHandler
from flask import Flask
from flask_login import LoginManager
from flask_session import Session
from .config import Config

login_manager = LoginManager()
sess = Session()

# ===== APP VERSION (跟 git tag / commit 同步) =====
APP_VERSION = 'v2.5.3'
APP_BUILD_DATE = '2026-05-25'


def create_app(config: Config = None):
    app = Flask(__name__, instance_relative_config=False)

    if config is None:
        config = Config()
    app.config.from_object(config)

    # ===== Jinja2 custom filters (v2.5) =====
    def humanize_bytes(n):
        try:
            n = int(n)
        except (ValueError, TypeError):
            return n
        for u, t in (('GB', 1024**3), ('MB', 1024**2), ('KB', 1024)):
            if n >= t:
                v = n / t
                return f'{v:.1f} {u}' if v < 100 else f'{int(v)} {u}'
        return f'{n} B'

    def humanize_age(start, end=None):
        from datetime import datetime, timezone
        if not start:
            return '-'
        if end is None:
            end = datetime.now(timezone.utc)
        if start.tzinfo is None:
            start = start.replace(tzinfo=timezone.utc)
        diff = end - start
        days = diff.days
        hours = diff.seconds // 3600
        mins = (diff.seconds % 3600) // 60
        if days > 0:
            return f'{days} 天 {hours} 時'
        if hours > 0:
            return f'{hours} 時 {mins} 分'
        if mins > 0:
            return f'{mins} 分'
        return f'{diff.seconds} 秒'

    app.jinja_env.filters['humanize_bytes'] = humanize_bytes
    app.jinja_env.filters['humanize_age'] = humanize_age

    # ===== Inject app version into all templates =====
    @app.context_processor
    def inject_version():
        return {'app_version': APP_VERSION, 'app_build_date': APP_BUILD_DATE}

    # ===== Logging =====
    log_dir = config.PORTAL_LOG_DIR
    os.makedirs(log_dir, exist_ok=True)
    log_file = os.path.join(log_dir, 'app.log')

    handler = RotatingFileHandler(log_file, maxBytes=20 * 1024 * 1024, backupCount=10, encoding='utf-8')
    formatter = logging.Formatter('%(asctime)s %(levelname)-5s [%(name)s] %(message)s')
    handler.setFormatter(formatter)
    handler.setLevel(logging.DEBUG if config.DEBUG else logging.INFO)
    app.logger.addHandler(handler)
    app.logger.setLevel(logging.DEBUG if config.DEBUG else logging.INFO)
    app.logger.info('SF Portal starting up...')

    # ===== Session (filesystem store) =====
    app.config['SESSION_TYPE'] = 'filesystem'
    app.config['SESSION_FILE_DIR'] = os.path.join(log_dir, 'sessions')
    app.config['SESSION_PERMANENT'] = False
    sess.init_app(app)

    # ===== Login =====
    login_manager.init_app(app)
    login_manager.login_view = 'auth.login'
    login_manager.session_protection = 'strong'

    from .auth import User, load_user
    login_manager.user_loader(load_user)

    # ===== Blueprints =====
    from .blueprints.main import main_bp
    from .blueprints.auth import auth_bp
    from .blueprints.approval import approval_bp
    from .blueprints.audit import audit_bp
    from .blueprints.admin import admin_bp
    from .blueprints.api import api_bp

    app.register_blueprint(main_bp)
    app.register_blueprint(auth_bp, url_prefix='/auth')
    app.register_blueprint(approval_bp, url_prefix='/approval')
    app.register_blueprint(audit_bp, url_prefix='/audit')
    app.register_blueprint(admin_bp, url_prefix='/admin')
    app.register_blueprint(api_bp, url_prefix='/api')

    # ===== Request hook (log every request to AuditLog) =====
    from .audit_helper import log_audit

    @app.before_request
    def log_request():
        from flask import request
        from flask_login import current_user
        if current_user.is_authenticated and request.endpoint not in ('api.health', 'static'):
            app.logger.info(f'[VIEW] {request.path} by {current_user.id}')

    @app.errorhandler(404)
    def page_not_found(e):
        from flask import render_template
        try:
            return render_template('error.html', code=404, msg='Page not found'), 404
        except Exception:
            return '<h1>404</h1><p>Page not found</p><a href="/">回首頁</a>', 404

    @app.errorhandler(500)
    def internal_error(e):
        app.logger.exception('[ERROR] 500 internal')
        import traceback
        tb = traceback.format_exc()
        # 試 render template, 失敗 fallback 純 HTML (避免 template 又炸再 500 loop)
        try:
            from flask import render_template
            return render_template('error.html', code=500, msg='Internal server error'), 500
        except Exception:
            debug_block = ''
            if app.config.get('DEBUG'):
                import html as _html
                debug_block = f'<pre style="background:#fee;padding:10px;font-size:11px;overflow:auto;">{_html.escape(tb)}</pre>'
            return (f'<!DOCTYPE html><html><head><meta charset="UTF-8">'
                    f'<title>500</title></head><body style="font-family:sans-serif;padding:40px;">'
                    f'<h1 style="font-size:60px;margin:0;color:#c00;">500</h1>'
                    f'<h2>Internal server error</h2>'
                    f'<p>請聯絡 IT 管理員, 或回到 <a href="/">首頁</a>.</p>'
                    f'{debug_block}'
                    f'</body></html>'), 500

    app.logger.info('SF Portal ready.')
    return app
