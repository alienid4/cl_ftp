-- SF File Exchange AuditLog DB Schema (PostgreSQL 版)
-- 對應 SQL Server: sql/01_create_db.sql
-- 規畫: 三層帳號 + 批次簽核 + chain_id + CEF 預留欄位

-- === AuditLog 主表 ===
CREATE TABLE IF NOT EXISTS audit_log (
    id              BIGSERIAL PRIMARY KEY,
    event_time      TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    event_type      VARCHAR(32) NOT NULL,           -- UPLOAD, APPROVE, REJECT, DOWNLOAD, LOGIN, etc.
    actor_user      VARCHAR(64),                    -- 操作者帳號
    actor_dept      VARCHAR(32),
    source_ip       VARCHAR(45),
    source_system   VARCHAR(16),                    -- SFTP / FTPS / PORTAL / SMB / SCHED / ADMIN / PAM
    protocol        VARCHAR(16),
    business_code   VARCHAR(16),                    -- u01, u02...
    batch_id        VARCHAR(64),                    -- 同批檔共用
    target_path     VARCHAR(512),
    target_file     VARCHAR(256),
    file_size       BIGINT,
    file_hash       VARCHAR(128),                   -- SHA-256
    result          VARCHAR(16),                    -- SUCCESS / FAIL / DENIED / TIMEOUT
    detail          JSONB,                          -- JSON 額外資訊 (Postgres 原生支援)
    chain_id        VARCHAR(64),                    -- 跨系統事件鏈
    pam_request_id  VARCHAR(64),
    -- SIEM 預留 (階段二接 forwarder)
    cef_signature   VARCHAR(64),
    cef_severity    SMALLINT,
    syslog_facility VARCHAR(16)
);

CREATE INDEX IF NOT EXISTS idx_audit_time     ON audit_log (event_time DESC);
CREATE INDEX IF NOT EXISTS idx_audit_user     ON audit_log (actor_user, event_time DESC);
CREATE INDEX IF NOT EXISTS idx_audit_business ON audit_log (business_code, event_time DESC);
CREATE INDEX IF NOT EXISTS idx_audit_batch    ON audit_log (batch_id);
CREATE INDEX IF NOT EXISTS idx_audit_chain    ON audit_log (chain_id);

COMMENT ON TABLE audit_log IS 'SF 主機所有事件審計紀錄 (對齊主管圖稽核要求)';

-- === 業務代號表 ===
CREATE TABLE IF NOT EXISTS business_code (
    code            VARCHAR(16) PRIMARY KEY,         -- u01, u02...
    dept            VARCHAR(32) NOT NULL,            -- HR, FIN, OPS, etc.
    description     VARCHAR(256),
    owner_ad        VARCHAR(64),                     -- 業務負責人 AD 帳號
    approvers_group VARCHAR(64),                     -- AD 群組: g_u0X_approvers
    samba_target    VARCHAR(128),                    -- 簽核通過後搬到 /data/exchange/samba/<dept>/
    allowed_proto   VARCHAR(16) DEFAULT 'SFTP',      -- SFTP, FTPS, BOTH
    enabled         BOOLEAN DEFAULT TRUE,
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- === 批次表 ===
CREATE TABLE IF NOT EXISTS batch (
    batch_id        VARCHAR(64) PRIMARY KEY,
    business_code   VARCHAR(16) REFERENCES business_code(code),
    uploader        VARCHAR(64),
    source_ip       VARCHAR(45),
    file_count      INT DEFAULT 0,
    total_size      BIGINT DEFAULT 0,
    status          VARCHAR(16),                     -- PENDING, APPROVED, REJECTED, MIXED, EXPIRED
    first_upload    TIMESTAMP WITH TIME ZONE,
    last_upload     TIMESTAMP WITH TIME ZONE,
    closed_at       TIMESTAMP WITH TIME ZONE,
    decided_at      TIMESTAMP WITH TIME ZONE,
    decided_by      VARCHAR(64),
    expires_at      TIMESTAMP WITH TIME ZONE,
    note            VARCHAR(512)
);

CREATE INDEX IF NOT EXISTS idx_batch_status ON batch (status, expires_at);
CREATE INDEX IF NOT EXISTS idx_batch_biz    ON batch (business_code, status);

-- === 批次內檔案 ===
CREATE TABLE IF NOT EXISTS batch_file (
    id              BIGSERIAL PRIMARY KEY,
    batch_id        VARCHAR(64) REFERENCES batch(batch_id) ON DELETE CASCADE,
    file_name       VARCHAR(256) NOT NULL,
    file_size       BIGINT,
    file_hash       VARCHAR(128),
    inbound_path    VARCHAR(512),
    decision        VARCHAR(16),                     -- APPROVED, REJECTED, PENDING
    decided_by      VARCHAR(64),
    decided_at      TIMESTAMP WITH TIME ZONE
);

CREATE INDEX IF NOT EXISTS idx_batch_file_batch ON batch_file (batch_id);

-- === View: 完整簽核狀態 ===
CREATE OR REPLACE VIEW v_batch_full AS
SELECT
    b.batch_id,
    b.business_code,
    bc.dept,
    b.uploader,
    b.file_count,
    b.total_size,
    b.status,
    b.first_upload,
    b.expires_at,
    EXTRACT(EPOCH FROM (b.expires_at - NOW())) / 86400 AS days_remaining
FROM batch b
LEFT JOIN business_code bc ON b.business_code = bc.code
WHERE b.status = 'PENDING';

COMMENT ON VIEW v_batch_full IS '待簽核批次完整資訊 (Portal 主畫面用)';

-- === 給 portal 帳號權限 ===
-- (08_setup_postgresql.sh 已 GRANT ALL, 此處保留註解)
-- GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO portal;
-- GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO portal;

-- === 初始 seed ===
-- v2.0.0.1: PoC 階段先 1 個測試帳號 u01t, 正式上線時再加 u01/u02/u03
INSERT INTO business_code (code, dept, description, samba_target, allowed_proto, enabled)
VALUES
    ('u01t', 'TEST', 'PoC 測試帳號', '/data/exchange/samba/test', 'SFTP', TRUE)
ON CONFLICT (code) DO NOTHING;

-- 之後正式上線加業務代號:
-- INSERT INTO business_code (code, dept, description, samba_target, allowed_proto)
-- VALUES
--     ('u01', 'HR',  'HR 部門檔案交換', '/data/exchange/samba/hr', 'SFTP'),
--     ('u02', 'FIN', 'Finance 部門檔案交換', '/data/exchange/samba/finance', 'SFTP'),
--     ('u03', 'OPS', 'Operations 部門檔案交換', '/data/exchange/samba/security', 'SFTP');

-- 完成
SELECT 'Schema 部署完成' AS result;
