#!/usr/bin/env python3
"""
SF Portal — batch_aggregator (v2.5)
每 5 秒掃 /data/exchange/u0X/inbound/, 新檔聚合進 batch + batchfile.
邏輯: 同 u0X + 同來源 IP + 30s 內視為同批; 5 分鐘安全閥強制 close.
v2.5: 加 source_host (PTR 反查) + file_ext.
"""
import os, sys, re, socket, subprocess, hashlib
from datetime import datetime, timedelta, timezone
from pathlib import Path
import psycopg2, psycopg2.extras

DB_DSN = 'postgresql://portal:portalpass_test@127.0.0.1:5432/file_exchange_audit'
DATA_ROOT = '/data/exchange'
USERS = ('u01', 'u02', 'u03', 'u04')
IDLE_SEC = 30
SAFETY_MIN = 5
FILE_QUIET_SEC = 5


def reverse_dns(ip):
    try:
        return socket.gethostbyaddr(ip)[0]
    except Exception:
        return None


def get_recent_sftp_ip(user):
    try:
        out = subprocess.run(
            ['journalctl', '-u', 'sshd', '--since', '10 min ago', '--no-pager'],
            capture_output=True, text=True, timeout=5
        ).stdout
        pat = re.compile(r'Accepted (?:password|publickey) for ' + re.escape(user) + r' from (\S+) port')
        ips = pat.findall(out)
        return ips[-1] if ips else '127.0.0.1'
    except Exception:
        return '127.0.0.1'


def file_hash(path, max_bytes=10 * 1024 * 1024):
    h = hashlib.sha256()
    try:
        with open(path, 'rb') as f:
            while True:
                chunk = f.read(65536)
                if not chunk:
                    break
                h.update(chunk)
                if f.tell() > max_bytes:
                    break
        return h.hexdigest()
    except Exception:
        return None


def audit(conn, event_type, source_system, actor, business_code, batch_id, target_file=None, file_size=None, result='SUCCESS'):
    with conn.cursor() as c:
        c.execute(
            '''INSERT INTO auditlog
            (event_type, source_system, actor_user, business_code, batch_id, target_file, file_size, result, cef_signature, cef_severity)
            VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)''',
            (event_type, source_system, actor, business_code, batch_id, target_file, file_size, result,
             'SF-200' if event_type == 'SFTP_UPLOAD' else 'SF-210', 3))


def aggregate():
    conn = psycopg2.connect(DB_DSN)
    conn.autocommit = False
    try:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            now_utc = datetime.now(timezone.utc)
            for user in USERS:
                inbound = Path(DATA_ROOT) / user / 'inbound'
                if not inbound.is_dir():
                    continue
                src_ip = get_recent_sftp_ip(user)
                src_host = reverse_dns(src_ip)

                for f in sorted(inbound.iterdir()):
                    if not f.is_file():
                        continue
                    mtime = datetime.fromtimestamp(f.stat().st_mtime, tz=timezone.utc)
                    if (now_utc - mtime).total_seconds() < FILE_QUIET_SEC:
                        continue

                    abs_path = str(f.resolve())
                    cur.execute('SELECT 1 FROM batchfile WHERE file_path=%s', (abs_path,))
                    if cur.fetchone():
                        continue

                    size = f.stat().st_size
                    h = file_hash(f) or ''
                    ext = f.suffix.lstrip('.').lower() if f.suffix else ''

                    cur.execute('''SELECT batch_id FROM batch
                        WHERE business_code=%s AND source_ip=%s AND status='OPEN'
                          AND last_file_at > %s
                        ORDER BY last_file_at DESC LIMIT 1''',
                        (user, src_ip, now_utc - timedelta(seconds=IDLE_SEC)))
                    row = cur.fetchone()

                    if row:
                        batch_id = row['batch_id']
                        cur.execute('''UPDATE batch SET file_count=file_count+1, total_size=total_size+%s,
                            last_file_at=%s WHERE batch_id=%s''',
                            (size, now_utc, batch_id))
                    else:
                        ts = now_utc.strftime('%Y%m%d-%H%M')
                        cur.execute('SELECT count(*) AS c FROM batch WHERE batch_id LIKE %s', (f'{user}-{ts}-%',))
                        seq = cur.fetchone()['c'] + 1
                        batch_id = f'{user}-{ts}-{seq:03d}'
                        cur.execute('''INSERT INTO batch (batch_id, business_code, source_ip, source_host,
                            first_file_at, last_file_at, file_count, total_size, status)
                            VALUES (%s,%s,%s,%s,%s,%s,1,%s,'OPEN')''',
                            (batch_id, user, src_ip, src_host, now_utc, now_utc, size))

                    cur.execute('''INSERT INTO batchfile
                        (batch_id, file_name, file_path, file_size, file_hash, upload_time, file_ext, virus_scan)
                        VALUES (%s,%s,%s,%s,%s,%s,%s,%s)''',
                        (batch_id, f.name, abs_path, size, h, mtime, ext, 'PENDING'))

                    audit(conn, 'SFTP_UPLOAD', 'SFTP', user, user, batch_id, f.name, size)
                    print(f'[INGEST] {user} {f.name} -> {batch_id}')

                cur.execute('''UPDATE batch SET status='PENDING_APPROVAL', closed_at=%s, close_reason='IDLE_30S'
                    WHERE business_code=%s AND status='OPEN' AND last_file_at <= %s
                    RETURNING batch_id, file_count''',
                    (now_utc, user, now_utc - timedelta(seconds=IDLE_SEC)))
                for r in cur.fetchall():
                    audit(conn, 'BATCH_PENDING', 'SCHED', None, user, r['batch_id'])
                    print(f'[CLOSE-IDLE] {r["batch_id"]} ({r["file_count"]} files)')

                cur.execute('''UPDATE batch SET status='PENDING_APPROVAL', closed_at=%s, close_reason='SAFETY_5MIN'
                    WHERE business_code=%s AND status='OPEN' AND first_file_at <= %s
                    RETURNING batch_id, file_count''',
                    (now_utc, user, now_utc - timedelta(minutes=SAFETY_MIN)))
                for r in cur.fetchall():
                    audit(conn, 'BATCH_PENDING', 'SCHED', None, user, r['batch_id'])
                    print(f'[CLOSE-SAFETY] {r["batch_id"]} ({r["file_count"]} files)')

        conn.commit()
    except Exception as e:
        conn.rollback()
        print(f'[ERROR] {e}', file=sys.stderr)
        sys.exit(1)
    finally:
        conn.close()


if __name__ == '__main__':
    aggregate()
