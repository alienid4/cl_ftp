"""
SF Portal — WSGI Entry Point
用 waitress 啟動 (Windows-friendly WSGI server)。
NSSM 把這支程式註冊成 Windows Service `FileExchangePortal`。

NSSM 設定:
    nssm install FileExchangePortal "D:\_portal\app\.venv\Scripts\python.exe"
    nssm set FileExchangePortal AppParameters "D:\_portal\app\wsgi.py"
    nssm set FileExchangePortal AppDirectory "D:\_portal\app"
    nssm set FileExchangePortal Start SERVICE_AUTO_START

直接執行 (開發測試):
    python wsgi.py
"""
from waitress import serve
from app import create_app
from app.config import Config

if __name__ == '__main__':
    app = create_app()
    serve(
        app,
        host='127.0.0.1',          # 只聽 localhost, 由 IIS 反向代理對外
        port=5000,
        threads=8,                 # 並行處理數
        connection_limit=200,
        cleanup_interval=30,
        channel_timeout=120,
        ident='SF-Portal'
    )
