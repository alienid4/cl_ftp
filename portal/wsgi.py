"""
SF Portal — WSGI Entry Point (multi-platform)

Linux (RHEL) + gunicorn:
    gunicorn --workers 3 --bind 127.0.0.1:5000 wsgi:app
    → gunicorn import wsgi 模組, 拿 module-level `app` 變數

Windows + waitress (NSSM 把這支程式註冊成 Windows Service):
    python wsgi.py
    → 走 __main__ 用 waitress.serve

開發 (任一 OS):
    python wsgi.py    → 沒 waitress 時 fallback Flask 內建 dev server
"""
from app import create_app

# module-level app — gunicorn / mod_wsgi / uWSGI 都用這個
app = create_app()


if __name__ == '__main__':
    # 直接執行: Windows / 開發
    try:
        from waitress import serve
        serve(
            app,
            host='127.0.0.1',
            port=5000,
            threads=8,
            connection_limit=200,
            cleanup_interval=30,
            channel_timeout=120,
            ident='SF-Portal'
        )
    except ImportError:
        # 沒裝 waitress (例如 Linux 用 gunicorn 的環境誤入 __main__) → Flask 內建
        app.run(host='127.0.0.1', port=5000, debug=False)
