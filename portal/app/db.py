"""
SF Portal — DB Helper (psycopg2 / PostgreSQL)

歷史背景:
    原版用 pyodbc + MSSQL (SCOPE_IDENTITY / SYSUTCDATETIME / `?` placeholder)
    2026-05-22 改為 psycopg2 + PostgreSQL, caller 介面不變 (`?` 跟
    SYSUTCDATETIME() 仍可用), 由本層自動翻譯.
"""
import re
import psycopg2
import psycopg2.extras
from contextlib import contextmanager
from flask import current_app


# ===== SQL 翻譯層 (MSSQL → PostgreSQL) =====

def _translate_sql(sql: str) -> str:
    """MSSQL → PostgreSQL 語法翻譯

    - `?` placeholder → `%s` (psycopg2 標準)
    - `SYSUTCDATETIME()` → `(NOW() AT TIME ZONE 'UTC')`
    - `SELECT TOP N ...` → `SELECT ... LIMIT N` (PG TOP 語法不存在)
    - `SCOPE_IDENTITY()` 處理 → execute_returning_id 自己加 RETURNING
    """
    # 1. ? → %s (但要小心: 已是 %s 的不要轉雙重)
    sql = re.sub(r'\?', '%s', sql)
    # 2. SYSUTCDATETIME() → (NOW() AT TIME ZONE 'UTC')
    sql = re.sub(r'\bSYSUTCDATETIME\(\)', "(NOW() AT TIME ZONE 'UTC')", sql, flags=re.IGNORECASE)
    # 3. SELECT TOP N ... → SELECT ... LIMIT N (移到尾端)
    top_match = re.search(r'\bSELECT\s+TOP\s+(\d+)\s+', sql, flags=re.IGNORECASE)
    if top_match:
        n = top_match.group(1)
        sql = re.sub(r'\bSELECT\s+TOP\s+\d+\s+', 'SELECT ', sql, count=1, flags=re.IGNORECASE)
        sql = sql.rstrip().rstrip(';').rstrip() + f' LIMIT {n}'
    return sql


# ===== Connection helper =====

@contextmanager
def get_conn():
    """取得 DB 連線 (context manager, 自動 commit/rollback/close)"""
    dsn = current_app.config['DB_CONNECTION_STRING']
    conn = psycopg2.connect(dsn)
    conn.autocommit = False
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def _dict_cursor(conn):
    """回傳會吐 dict 的 cursor (psycopg2.extras.RealDictCursor)"""
    return conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)


# ===== 共用低階 API (跟原 db.py 介面同) =====

def query(sql: str, params: tuple = None) -> list:
    """執行 SELECT, 回傳 list of dict"""
    sql_pg = _translate_sql(sql)
    with get_conn() as conn:
        cur = _dict_cursor(conn)
        cur.execute(sql_pg, params or ())
        return [dict(row) for row in cur.fetchall()]


def query_one(sql: str, params: tuple = None):
    """執行 SELECT, 回傳第一筆 dict 或 None"""
    rows = query(sql, params)
    return rows[0] if rows else None


def execute(sql: str, params: tuple = None) -> int:
    """執行 INSERT/UPDATE/DELETE, 回傳 rowcount"""
    sql_pg = _translate_sql(sql)
    with get_conn() as conn:
        cur = conn.cursor()
        cur.execute(sql_pg, params or ())
        return cur.rowcount


def execute_returning_id(sql: str, params: tuple = None) -> int:
    """執行 INSERT 並回傳新建立的 id

    原 MSSQL 寫法是 caller 在 SQL 內帶 SCOPE_IDENTITY().
    PostgreSQL 用 RETURNING id, 本 function 自動加.
    """
    sql_pg = _translate_sql(sql)
    # 自動加 RETURNING id (如果 caller 沒加)
    if 'RETURNING' not in sql_pg.upper():
        sql_pg = sql_pg.rstrip(';').rstrip() + ' RETURNING id'
    with get_conn() as conn:
        cur = conn.cursor()
        cur.execute(sql_pg, params or ())
        row = cur.fetchone()
        return int(row[0]) if row else 0


# ===== Schema-level helpers (對應原 db.py) =====
# 注意: 假設 schema 用 INTEGER 0/1 表示 boolean (跟 MSSQL 一致),
#       不用 PostgreSQL 原生 BOOLEAN type, 減少 caller 修改

def get_business_codes(active_only: bool = True) -> list:
    sql = "SELECT * FROM BusinessCode"
    if active_only:
        sql += " WHERE is_active = 1"
    sql += " ORDER BY code"
    return query(sql)


def get_business_code(code: str):
    return query_one("SELECT * FROM BusinessCode WHERE code = ?", (code,))


def get_user_pending_batches(ad_account: str) -> list:
    """取得 ad_account 待簽的批次清單"""
    sql = """
    SELECT b.*, bc.name AS business_name
    FROM Batch b
    JOIN BusinessCode bc ON b.business_code = bc.code
    WHERE b.status = 'PENDING_APPROVAL'
      AND EXISTS (
          SELECT 1 FROM PortalUser u WHERE u.ad_account = ?
          -- (實際應加 AD 群組成員檢查, 此處簡化)
      )
    ORDER BY b.last_file_at DESC
    """
    return query(sql, (ad_account,))


def get_batch_files(batch_id: str) -> list:
    return query("SELECT * FROM BatchFile WHERE batch_id = ? ORDER BY id", (batch_id,))


def get_batch(batch_id: str):
    return query_one("SELECT * FROM Batch WHERE batch_id = ?", (batch_id,))


def approve_batch(batch_id: str, ad_account: str) -> bool:
    """ANY 制 — 任 1 同意即放行"""
    rc = execute("""
        UPDATE Batch
        SET status = 'APPROVED', approved_by = ?, approved_at = SYSUTCDATETIME()
        WHERE batch_id = ? AND status = 'PENDING_APPROVAL'
    """, (ad_account, batch_id))
    return rc > 0


def reject_batch(batch_id: str, ad_account: str, reason: str) -> bool:
    rc = execute("""
        UPDATE Batch
        SET status = 'REJECTED', approved_by = ?, approved_at = SYSUTCDATETIME(),
            reject_reason = ?
        WHERE batch_id = ? AND status = 'PENDING_APPROVAL'
    """, (ad_account, reason, batch_id))
    return rc > 0
