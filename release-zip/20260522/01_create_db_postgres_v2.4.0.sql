-- ============================================
-- SF AuditLog Database Schema (PostgreSQL 13+)
-- v2.4.0 — 表名對齊 caller code (PG 折成 lowercase no-underscore)
--
-- 設計原則:
--   - 表名跟原 MSSQL CamelCase 折成 PG 後一致:
--       AuditLog       → auditlog
--       BusinessCode   → businesscode
--       Batch          → batch
--       BatchFile      → batchfile
--       PortalUser     → portaluser
--       SambaPathHistory → sambapathhistory
--       V_AuditLog_Detail → v_auditlog_detail
--   - boolean 用 INTEGER 0/1 (跟 MSSQL BIT 行為一致, caller 不用改)
--   - DATETIME2 → TIMESTAMP WITH TIME ZONE
--   - NVARCHAR → VARCHAR (PG 原生 UTF-8, 不用 N 前綴)
--   - BIGINT IDENTITY(1,1) → BIGSERIAL
--   - SYSUTCDATETIME() default → (NOW() AT TIME ZONE 'UTC')
-- ============================================

-- AuditLog 主表
CREATE TABLE IF NOT EXISTS auditlog (
    id                  BIGSERIAL PRIMARY KEY,
    event_time          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT (NOW() AT TIME ZONE 'UTC'),
    event_type          VARCHAR(32)  NOT NULL,
    source_system       VARCHAR(16)  NOT NULL,
    protocol            VARCHAR(16),
    actor_user          VARCHAR(128),
    actor_dept          VARCHAR(64),
    source_ip           VARCHAR(45),
    business_code       VARCHAR(16),
    batch_id            VARCHAR(64),
    target_path         VARCHAR(512),
    target_file         VARCHAR(256),
    file_size           BIGINT,
    file_hash           VARCHAR(128),
    result              VARCHAR(16)  NOT NULL DEFAULT 'SUCCESS',
    detail              TEXT,
    chain_id            VARCHAR(64),
    pam_request_id      VARCHAR(64),
    cef_signature       VARCHAR(64),
    cef_severity        SMALLINT,
    syslog_facility     VARCHAR(16),
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT (NOW() AT TIME ZONE 'UTC')
);

CREATE INDEX IF NOT EXISTS idx_auditlog_time     ON auditlog (event_time DESC);
CREATE INDEX IF NOT EXISTS idx_auditlog_user     ON auditlog (actor_user, event_time DESC);
CREATE INDEX IF NOT EXISTS idx_auditlog_business ON auditlog (business_code, event_time DESC);
CREATE INDEX IF NOT EXISTS idx_auditlog_batch    ON auditlog (batch_id);
CREATE INDEX IF NOT EXISTS idx_auditlog_chain    ON auditlog (chain_id);
CREATE INDEX IF NOT EXISTS idx_auditlog_file     ON auditlog (target_file);
CREATE INDEX IF NOT EXISTS idx_auditlog_result   ON auditlog (result, event_time);

-- BusinessCode
CREATE TABLE IF NOT EXISTS businesscode (
    code                VARCHAR(16) PRIMARY KEY,
    name                VARCHAR(128) NOT NULL,
    owner_ad            VARCHAR(128) NOT NULL,
    approver_ad_group   VARCHAR(128) NOT NULL,
    samba_dir           VARCHAR(64)  NOT NULL,
    download_ad_group   VARCHAR(128) NOT NULL,
    retention_days      INTEGER      NOT NULL DEFAULT 7,
    allow_protocols     VARCHAR(32)  NOT NULL DEFAULT 'SFTP',
    description         VARCHAR(512),
    is_active           INTEGER      NOT NULL DEFAULT 1,
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT (NOW() AT TIME ZONE 'UTC'),
    created_by          VARCHAR(128),
    updated_at          TIMESTAMP WITH TIME ZONE,
    updated_by          VARCHAR(128)
);

CREATE INDEX IF NOT EXISTS idx_businesscode_active ON businesscode (is_active);

-- Batch
CREATE TABLE IF NOT EXISTS batch (
    batch_id            VARCHAR(64) PRIMARY KEY,
    business_code       VARCHAR(16) NOT NULL,
    source_ip           VARCHAR(45) NOT NULL,
    first_file_at       TIMESTAMP WITH TIME ZONE NOT NULL,
    last_file_at        TIMESTAMP WITH TIME ZONE NOT NULL,
    closed_at           TIMESTAMP WITH TIME ZONE,
    close_reason        VARCHAR(16),
    file_count          INTEGER NOT NULL DEFAULT 0,
    total_size          BIGINT  NOT NULL DEFAULT 0,
    status              VARCHAR(16) NOT NULL DEFAULT 'OPEN',
    approved_by         VARCHAR(128),
    approved_at         TIMESTAMP WITH TIME ZONE,
    reject_reason       VARCHAR(512),
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT (NOW() AT TIME ZONE 'UTC')
);

CREATE INDEX IF NOT EXISTS idx_batch_business ON batch (business_code);
CREATE INDEX IF NOT EXISTS idx_batch_status   ON batch (status);
CREATE INDEX IF NOT EXISTS idx_batch_lastfile ON batch (last_file_at) WHERE status = 'OPEN';

-- BatchFile
CREATE TABLE IF NOT EXISTS batchfile (
    id                  BIGSERIAL PRIMARY KEY,
    batch_id            VARCHAR(64) NOT NULL REFERENCES batch (batch_id) ON DELETE CASCADE,
    file_name           VARCHAR(256) NOT NULL,
    file_path           VARCHAR(512) NOT NULL,
    file_size           BIGINT NOT NULL,
    file_hash           VARCHAR(128),
    upload_time         TIMESTAMP WITH TIME ZONE NOT NULL,
    decision            VARCHAR(16),
    decision_by         VARCHAR(128),
    decision_at         TIMESTAMP WITH TIME ZONE,
    final_path          VARCHAR(512),
    moved_at            TIMESTAMP WITH TIME ZONE
);

CREATE INDEX IF NOT EXISTS idx_batchfile_batch ON batchfile (batch_id);

-- PortalUser
CREATE TABLE IF NOT EXISTS portaluser (
    ad_account          VARCHAR(128) PRIMARY KEY,
    display_name        VARCHAR(128),
    email               VARCHAR(256),
    department          VARCHAR(64),
    first_login_at      TIMESTAMP WITH TIME ZONE,
    last_login_at       TIMESTAMP WITH TIME ZONE,
    login_count         INTEGER NOT NULL DEFAULT 0,
    is_admin            INTEGER NOT NULL DEFAULT 0,
    is_active           INTEGER NOT NULL DEFAULT 1
);

CREATE INDEX IF NOT EXISTS idx_portaluser_email ON portaluser (email);
CREATE INDEX IF NOT EXISTS idx_portaluser_admin ON portaluser (is_admin) WHERE is_admin = 1;

-- SambaPathHistory
CREATE TABLE IF NOT EXISTS sambapathhistory (
    id                  BIGSERIAL PRIMARY KEY,
    business_code       VARCHAR(16)  NOT NULL,
    old_path            VARCHAR(128),
    new_path            VARCHAR(128) NOT NULL,
    changed_by          VARCHAR(128) NOT NULL,
    changed_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT (NOW() AT TIME ZONE 'UTC'),
    notified_count      INTEGER,
    notes               VARCHAR(512)
);

CREATE INDEX IF NOT EXISTS idx_sambapath_business ON sambapathhistory (business_code, changed_at);

-- V_AuditLog_Detail view
CREATE OR REPLACE VIEW v_auditlog_detail AS
SELECT
    a.id,
    a.event_time,
    a.event_type,
    a.source_system,
    a.actor_user,
    u.display_name AS actor_name,
    a.actor_dept,
    a.source_ip,
    a.business_code,
    b.name AS business_name,
    a.batch_id,
    a.target_file,
    a.file_size,
    a.result,
    a.chain_id,
    a.detail
FROM auditlog a
LEFT JOIN portaluser u   ON a.actor_user    = u.ad_account
LEFT JOIN businesscode b ON a.business_code = b.code;

-- 初始 seed: 4 個示範業務代號 (對齊 MSSQL 版 01_create_db.sql)
INSERT INTO businesscode (code, name, owner_ad, approver_ad_group, samba_dir, download_ad_group, retention_days, allow_protocols, description)
VALUES
    ('u01', '架構科月結報表', 'CORP\zhang.ming',   'g_u01_approvers', 'architecture', 'dept_archi_view',    7, 'SFTP',      '架構科月結資料'),
    ('u02', '人資考勤資料',  'CORP\lee.dahua',    'g_u02_approvers', 'hr',           'dept_hr_view',       7, 'SFTP',      'HR 月度考勤'),
    ('u03', '財務沖銷',      'CORP\chen.officer', 'g_u03_approvers', 'finance',      'dept_finance_view',  7, 'SFTP',      '財務月結沖銷'),
    ('u04', '資安事件回報',  'CORP\wu.security',  'g_u04_approvers', 'security',     'dept_security_view', 7, 'SFTP+FTPS', '資安通報')
ON CONFLICT (code) DO NOTHING;

-- 完成
SELECT 'PostgreSQL schema v2.4.0 部署完成' AS result;
