"""
SF Portal — DB Helper (pyodbc)
所有 SQL 走這層, 不要散落到 blueprints。
"""
import pyodbc
from contextlib import contextmanager
from flask import current_app


@contextmanager
def get_conn():
    """取得 DB 連線 (context manager, 自動關閉)"""
    conn = pyodbc.connect(current_app.config['DB_CONNECTION_STRING'], autocommit=False)
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def query(sql: str, params: tuple = None) -> list[dict]:
    """執行 SELECT, 回傳 list of dict"""
    with get_conn() as conn:
        cur = conn.cursor()
        cur.execute(sql, params or ())
        cols = [c[0] for c in cur.description] if cur.description else []
        return [dict(zip(cols, row)) for row in cur.fetchall()]


def query_one(sql: str, params: tuple = None) -> dict | None:
    """執行 SELECT, 回傳第一筆 dict 或 None"""
    rows = query(sql, params)
    return rows[0] if rows else None


def execute(sql: str, params: tuple = None) -> int:
    """執行 INSERT/UPDATE/DELETE, 回傳 rowcount"""
    with get_conn() as conn:
        cur = conn.cursor()
        cur.execute(sql, params or ())
        return cur.rowcount


def execute_returning_id(sql: str, params: tuple = None) -> int:
    """執行 INSERT 並回傳新建立的 id (假設用 SCOPE_IDENTITY())"""
    with get_conn() as conn:
        cur = conn.cursor()
        cur.execute(sql + '; SELECT SCOPE_IDENTITY() AS new_id;', params or ())
        cur.nextset()
        row = cur.fetchone()
        return int(row[0]) if row else 0


# ===== 共用 query 函式 =====
def get_business_codes(active_only: bool = True) -> list[dict]:
    sql = "SELECT * FROM BusinessCode"
    if active_only:
        sql += " WHERE is_active = 1"
    sql += " ORDER BY code"
    return query(sql)


def get_business_code(code: str) -> dict | None:
    return query_one("SELECT * FROM BusinessCode WHERE code = ?", (code,))


def get_user_pending_batches(ad_account: str) -> list[dict]:
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


def get_batch_files(batch_id: str) -> list[dict]:
    return query("SELECT * FROM BatchFile WHERE batch_id = ? ORDER BY id", (batch_id,))


def get_batch(batch_id: str) -> dict | None:
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
