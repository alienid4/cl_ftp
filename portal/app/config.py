"""
SF Portal — Config
從環境變數或 .env 讀取設定, 不寫死。
"""
import os
from pathlib import Path
from dotenv import load_dotenv

# 載入 .env (如果存在)
BASE_DIR = Path(__file__).resolve().parent.parent
load_dotenv(BASE_DIR / '.env')


def env_bool(key, default=False):
    val = os.getenv(key, str(default)).lower()
    return val in ('1', 'true', 'yes', 'on')


class Config:
    # Flask
    SECRET_KEY = os.getenv('SECRET_KEY', 'change-me-32-chars-random')
    SESSION_TIMEOUT_MIN = int(os.getenv('SESSION_TIMEOUT_MIN', '30'))
    DEBUG = env_bool('DEBUG', False)
    VERBOSE_LOG = env_bool('VERBOSE_LOG', False)

    # DB
    DB_MODE = os.getenv('DB_MODE', 'Express')  # Express / CorpDB
    DB_CONNECTION_STRING = os.getenv(
        'DB_CONNECTION_STRING',
        r'Server=.\SQLEXPRESS;Database=FileExchangeAudit;Trusted_Connection=yes;TrustServerCertificate=yes'
    )

    # AD / LDAP
    AD_SERVER = os.getenv('AD_SERVER', 'ldap://corp-dc01.corp.local')
    AD_BASE_DN = os.getenv('AD_BASE_DN', 'DC=corp,DC=local')
    AD_DOMAIN = os.getenv('AD_DOMAIN', 'CORP')
    AD_BIND_USER = os.getenv('AD_BIND_USER', '')
    AD_BIND_PASS = os.getenv('AD_BIND_PASS', '')
    AD_AUTH_MODE = os.getenv('AD_AUTH_MODE', 'simple')   # simple | ntlm
    PORTAL_BASE_URL = os.getenv('PORTAL_BASE_URL', 'http://localhost')

    # Mail
    SMTP_SERVER = os.getenv('SMTP_SERVER', 'mail-relay.corp.local')
    SMTP_PORT = int(os.getenv('SMTP_PORT', '25'))
    SMTP_USE_TLS = env_bool('SMTP_USE_TLS', False)
    SMTP_FROM = os.getenv('SMTP_FROM', 'sf-noreply@corp.local')
    ADMIN_EMAIL = os.getenv('ADMIN_EMAIL', 'it-admin@corp.local')

    # Paths
    DATA_EXCHANGE_ROOT = os.getenv('DATA_EXCHANGE_ROOT', r'D:\DataExchange')
    PORTAL_LOG_DIR = os.getenv('PORTAL_LOG_DIR', r'D:\_portal\logs')
    PORTAL_BACKUP_DIR = os.getenv('PORTAL_BACKUP_DIR', r'D:\_portal\backups')

    # Batch 邏輯
    BATCH_IDLE_SECONDS = int(os.getenv('BATCH_IDLE_SECONDS', '30'))
    BATCH_SAFETY_MINUTES = int(os.getenv('BATCH_SAFETY_MINUTES', '5'))
    APPROVAL_TIMEOUT_DAYS = int(os.getenv('APPROVAL_TIMEOUT_DAYS', '7'))

    # 保留期
    HOME_RETENTION_DAYS = int(os.getenv('HOME_RETENTION_DAYS', '7'))
    SAMBA_RETENTION_DAYS = int(os.getenv('SAMBA_RETENTION_DAYS', '7'))
    AUDITLOG_ONLINE_DAYS = int(os.getenv('AUDITLOG_ONLINE_DAYS', '365'))
