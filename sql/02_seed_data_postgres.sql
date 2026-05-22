-- ============================================
-- SF Portal — Demo seed data (v2.4.6)
-- 給 USER 看到頁面有東西, 不用真的 SFTP 上傳
--
-- 跑法: sudo -u postgres psql -d file_exchange_audit -f /var/lib/pgsql/02_seed_data_postgres.sql
-- ============================================

-- === 3 個 Batch ===
INSERT INTO batch (batch_id, business_code, source_ip, first_file_at, last_file_at, file_count, total_size, status)
VALUES
    ('u01-20260520-1432', 'u01', '10.20.5.31',
     (NOW() AT TIME ZONE 'UTC') - INTERVAL '2 hours',
     (NOW() AT TIME ZONE 'UTC') - INTERVAL '2 hours',
     5, 8400000, 'PENDING_APPROVAL'),
    ('u01-20260519-0915', 'u01', '10.20.5.31',
     (NOW() AT TIME ZONE 'UTC') - INTERVAL '1 day',
     (NOW() AT TIME ZONE 'UTC') - INTERVAL '1 day',
     1, 12600000, 'APPROVED'),
    ('u02-20260518-1100', 'u02', '10.20.5.32',
     (NOW() AT TIME ZONE 'UTC') - INTERVAL '2 days',
     (NOW() AT TIME ZONE 'UTC') - INTERVAL '2 days',
     3, 5200000, 'REJECTED')
ON CONFLICT (batch_id) DO NOTHING;

-- === 9 個 BatchFile ===
INSERT INTO batchfile (batch_id, file_name, file_path, file_size, upload_time, decision)
VALUES
    ('u01-20260520-1432', '月結_客戶清單.csv', '/data/exchange/u01/inbound/月結_客戶清單.csv', 2100000, (NOW() AT TIME ZONE 'UTC') - INTERVAL '2 hours', NULL),
    ('u01-20260520-1432', '月結_交易明細.csv', '/data/exchange/u01/inbound/月結_交易明細.csv', 3500000, (NOW() AT TIME ZONE 'UTC') - INTERVAL '2 hours', NULL),
    ('u01-20260520-1432', '月結_對帳.csv', '/data/exchange/u01/inbound/月結_對帳.csv', 820000, (NOW() AT TIME ZONE 'UTC') - INTERVAL '2 hours', NULL),
    ('u01-20260520-1432', '月結_統計.xlsx', '/data/exchange/u01/inbound/月結_統計.xlsx', 1200000, (NOW() AT TIME ZONE 'UTC') - INTERVAL '2 hours', NULL),
    ('u01-20260520-1432', '月結_附件.zip', '/data/exchange/u01/inbound/月結_附件.zip', 800000, (NOW() AT TIME ZONE 'UTC') - INTERVAL '2 hours', NULL),
    ('u01-20260519-0915', 'network_topology_v3.pdf', '/data/exchange/u01/inbound/network_topology_v3.pdf', 12600000, (NOW() AT TIME ZONE 'UTC') - INTERVAL '1 day', 'APPROVED'),
    ('u02-20260518-1100', 'hr_attendance_202605.csv', '/data/exchange/u02/inbound/hr_attendance_202605.csv', 2500000, (NOW() AT TIME ZONE 'UTC') - INTERVAL '2 days', 'REJECTED'),
    ('u02-20260518-1100', 'overtime_202605.csv', '/data/exchange/u02/inbound/overtime_202605.csv', 1700000, (NOW() AT TIME ZONE 'UTC') - INTERVAL '2 days', 'REJECTED'),
    ('u02-20260518-1100', 'leave_application.pdf', '/data/exchange/u02/inbound/leave_application.pdf', 1000000, (NOW() AT TIME ZONE 'UTC') - INTERVAL '2 days', 'REJECTED')
ON CONFLICT DO NOTHING;

-- === 10 個 AuditLog (近期事件, KPI 看得到數字) ===
INSERT INTO auditlog (event_time, event_type, source_system, actor_user, source_ip, business_code, batch_id, target_file, file_size, result, cef_signature, cef_severity)
VALUES
    ((NOW() AT TIME ZONE 'UTC') - INTERVAL '2 hours', 'SFTP_UPLOAD', 'SFTP', 'u01', '10.20.5.31', 'u01', 'u01-20260520-1432', '月結_客戶清單.csv', 2100000, 'SUCCESS', 'SF-200', 3),
    ((NOW() AT TIME ZONE 'UTC') - INTERVAL '2 hours', 'SFTP_UPLOAD', 'SFTP', 'u01', '10.20.5.31', 'u01', 'u01-20260520-1432', '月結_交易明細.csv', 3500000, 'SUCCESS', 'SF-200', 3),
    ((NOW() AT TIME ZONE 'UTC') - INTERVAL '2 hours', 'BATCH_PENDING', 'SCHED', NULL, NULL, 'u01', 'u01-20260520-1432', NULL, NULL, 'SUCCESS', 'SF-210', 3),
    ((NOW() AT TIME ZONE 'UTC') - INTERVAL '1 day', 'APPROVE_OK', 'PORTAL', 'CORP\lin.deputy', '10.30.1.88', 'u01', 'u01-20260519-0915', 'network_topology_v3.pdf', 12600000, 'SUCCESS', 'SF-300', 4),
    ((NOW() AT TIME ZONE 'UTC') - INTERVAL '1 day', 'MOVE_OK', 'PORTAL', 'CORP\lin.deputy', '10.30.1.88', 'u01', 'u01-20260519-0915', 'network_topology_v3.pdf', 12600000, 'SUCCESS', 'SF-400', 3),
    ((NOW() AT TIME ZONE 'UTC') - INTERVAL '2 days', 'APPROVE_REJECT', 'PORTAL', 'CORP\lee.hr', '10.30.1.50', 'u02', 'u02-20260518-1100', NULL, NULL, 'SUCCESS', 'SF-301', 4),
    ((NOW() AT TIME ZONE 'UTC') - INTERVAL '30 minutes', 'LOGIN_OK', 'PORTAL', 'CORP\admin', '10.30.0.1', NULL, NULL, NULL, NULL, 'SUCCESS', 'SF-100', 3),
    ((NOW() AT TIME ZONE 'UTC') - INTERVAL '4 hours', 'LOGIN_FAIL', 'PORTAL', 'CORP\unknown', '10.30.1.99', NULL, NULL, NULL, NULL, 'FAIL', 'SF-101', 5),
    ((NOW() AT TIME ZONE 'UTC') - INTERVAL '6 hours', 'DENIED', 'SMB', 'CORP\liu.other', '10.30.2.88', NULL, NULL, NULL, NULL, 'DENIED', 'SF-900', 7),
    ((NOW() AT TIME ZONE 'UTC') - INTERVAL '1 day', 'SMB_DOWNLOAD', 'SMB', 'CORP\zhang.viewer', '10.30.2.45', NULL, NULL, 'network_topology_v3.pdf', 12600000, 'SUCCESS', 'SF-500', 3)
ON CONFLICT DO NOTHING;

SELECT 'Seed data 完成 (v2.4.6)' AS result, count(*) AS auditlog_count FROM auditlog;
