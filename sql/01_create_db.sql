-- ============================================
-- SF AuditLog Database Schema
-- 對齊 plan: 含 batch_id / chain_id / CEF 預留欄位
-- 兼容 SQL Server Express (第一階段) 與 MS SQL Standard (第二階段)
-- ============================================

USE [master]
GO

-- 建立資料庫 (若不存在)
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = N'FileExchangeAudit')
BEGIN
    CREATE DATABASE [FileExchangeAudit]
    ON PRIMARY (
        NAME = N'FileExchangeAudit_Data',
        FILENAME = N'D:\_portal\db\FileExchangeAudit.mdf',
        SIZE = 100MB,
        MAXSIZE = 8000MB,             -- Express 上限 10 GB, 留 2 GB buffer
        FILEGROWTH = 100MB
    )
    LOG ON (
        NAME = N'FileExchangeAudit_Log',
        FILENAME = N'D:\_portal\db\FileExchangeAudit_log.ldf',
        SIZE = 50MB,
        MAXSIZE = 2000MB,
        FILEGROWTH = 50MB
    )
    COLLATE Chinese_Taiwan_Stroke_CI_AS;
END
GO

ALTER DATABASE [FileExchangeAudit] SET RECOVERY SIMPLE;  -- Express 不支援 FULL backup, 簡單即可
GO

USE [FileExchangeAudit]
GO

-- ============================================
-- AuditLog: 核心稽核紀錄表
-- ============================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'AuditLog')
BEGIN
    CREATE TABLE [dbo].[AuditLog] (
        [id]                BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        [event_time]        DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),

        -- 事件基本
        [event_type]        VARCHAR(32) NOT NULL,        -- LOGIN_OK / SFTP_UPLOAD / APPROVE_OK / DOWNLOAD_OK / DENIED 等
        [source_system]     VARCHAR(16) NOT NULL,        -- SFTP / FTPS / PORTAL / SMB / SCHED / ADMIN / PAM(階段二)
        [protocol]          VARCHAR(16) NULL,            -- SFTP / FTPS / HTTPS / SMB

        -- 操作者
        [actor_user]        VARCHAR(128) NULL,           -- 個人帳號 (CORP\xxx) 或業務代號 (u01)
        [actor_dept]        VARCHAR(64) NULL,            -- 部門 (從 AD 群組解析)
        [source_ip]         VARCHAR(45) NULL,            -- IPv4 / IPv6 通用

        -- 業務維度
        [business_code]     VARCHAR(16) NULL,            -- u01, u02, ...
        [batch_id]          VARCHAR(64) NULL,            -- 同批檔共用 (滑動 30s 聚合)

        -- 標的
        [target_path]       NVARCHAR(512) NULL,          -- 完整路徑
        [target_file]       NVARCHAR(256) NULL,          -- 檔名
        [file_size]         BIGINT NULL,                 -- bytes
        [file_hash]         VARCHAR(128) NULL,           -- SHA-256

        -- 結果
        [result]            VARCHAR(16) NOT NULL,        -- SUCCESS / FAIL / DENIED / TIMEOUT / PENDING
        [detail]            NVARCHAR(MAX) NULL,          -- JSON 補充

        -- 跨系統串接 (階段二)
        [chain_id]          VARCHAR(64) NULL,            -- 從 PAM 申請串到 SMB 下載
        [pam_request_id]    VARCHAR(64) NULL,            -- PAM 申請 ID

        -- SIEM 預留 (階段二, CEF / syslog 標準化)
        [cef_signature]     VARCHAR(64) NULL,            -- CEF Signature ID
        [cef_severity]      TINYINT NULL,                -- 0-10
        [syslog_facility]   VARCHAR(16) NULL,

        -- 系統
        [created_at]        DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
    );

    -- 索引
    CREATE INDEX IX_AuditLog_Time     ON [AuditLog] ([event_time]);
    CREATE INDEX IX_AuditLog_User     ON [AuditLog] ([actor_user], [event_time]);
    CREATE INDEX IX_AuditLog_Business ON [AuditLog] ([business_code], [event_time]);
    CREATE INDEX IX_AuditLog_Batch    ON [AuditLog] ([batch_id]);
    CREATE INDEX IX_AuditLog_Chain    ON [AuditLog] ([chain_id]);
    CREATE INDEX IX_AuditLog_File     ON [AuditLog] ([target_file]);
    CREATE INDEX IX_AuditLog_Result   ON [AuditLog] ([result], [event_time]) WHERE [result] IN ('FAIL', 'DENIED');

    PRINT N'AuditLog 表建立完成';
END
ELSE
    PRINT N'AuditLog 表已存在, 跳過';
GO

-- ============================================
-- BusinessCode: 業務代號設定表 (u01, u02, ...)
-- ============================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'BusinessCode')
BEGIN
    CREATE TABLE [dbo].[BusinessCode] (
        [code]              VARCHAR(16) NOT NULL PRIMARY KEY,   -- u01, u02...
        [name]              NVARCHAR(128) NOT NULL,             -- 架構科月結報表
        [owner_ad]          VARCHAR(128) NOT NULL,              -- CORP\zhang.ming 業務負責人
        [approver_ad_group] VARCHAR(128) NOT NULL,              -- g_u01_approvers AD 群組
        [samba_dir]         VARCHAR(64) NOT NULL,               -- architecture (對應 \\SF\architecture\)
        [download_ad_group] VARCHAR(128) NOT NULL,              -- dept_archi_view 可下載 AD 群組
        [retention_days]    INT NOT NULL DEFAULT 7,             -- home 與 samba 保留天數
        [allow_protocols]   VARCHAR(32) NOT NULL DEFAULT 'SFTP',-- SFTP, SFTP+FTPS
        [description]       NVARCHAR(512) NULL,                 -- 用途說明
        [is_active]         BIT NOT NULL DEFAULT 1,
        [created_at]        DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        [created_by]        VARCHAR(128) NULL,
        [updated_at]        DATETIME2 NULL,
        [updated_by]        VARCHAR(128) NULL
    );

    CREATE INDEX IX_BusinessCode_Active ON [BusinessCode] ([is_active]);
    PRINT N'BusinessCode 表建立完成';
END
GO

-- ============================================
-- Batch: 批次聚合表 (滑動 30 秒, 5 分鐘安全閥)
-- ============================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Batch')
BEGIN
    CREATE TABLE [dbo].[Batch] (
        [batch_id]          VARCHAR(64) NOT NULL PRIMARY KEY,   -- u01-20260518-1432
        [business_code]     VARCHAR(16) NOT NULL,
        [source_ip]         VARCHAR(45) NOT NULL,
        [first_file_at]     DATETIME2 NOT NULL,                 -- 批次開始時間
        [last_file_at]      DATETIME2 NOT NULL,                 -- 批次最後更新時間 (滑動窗口)
        [closed_at]         DATETIME2 NULL,                     -- 批次關閉時間 (觸發簽核時)
        [close_reason]      VARCHAR(16) NULL,                   -- IDLE_30S / SAFETY_5MIN / MANUAL
        [file_count]        INT NOT NULL DEFAULT 0,
        [total_size]        BIGINT NOT NULL DEFAULT 0,
        [status]            VARCHAR(16) NOT NULL DEFAULT 'OPEN',-- OPEN / PENDING_APPROVAL / APPROVED / REJECTED / TIMEOUT
        [approved_by]       VARCHAR(128) NULL,
        [approved_at]       DATETIME2 NULL,
        [reject_reason]     NVARCHAR(512) NULL,

        [created_at]        DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
    );

    CREATE INDEX IX_Batch_Business ON [Batch] ([business_code]);
    CREATE INDEX IX_Batch_Status   ON [Batch] ([status]);
    CREATE INDEX IX_Batch_OpenLast ON [Batch] ([last_file_at]) WHERE [status] = 'OPEN';
    PRINT N'Batch 表建立完成';
END
GO

-- ============================================
-- BatchFile: 批次內檔案 (per-file 細節, 支援細選簽核)
-- ============================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'BatchFile')
BEGIN
    CREATE TABLE [dbo].[BatchFile] (
        [id]                BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        [batch_id]          VARCHAR(64) NOT NULL,
        [file_name]         NVARCHAR(256) NOT NULL,
        [file_path]         NVARCHAR(512) NOT NULL,      -- D:\DataExchange\u01\inbound\xxx
        [file_size]         BIGINT NOT NULL,
        [file_hash]         VARCHAR(128) NULL,
        [upload_time]       DATETIME2 NOT NULL,

        -- 簽核細節 (per-file, 支援細選)
        [decision]          VARCHAR(16) NULL,            -- APPROVED / REJECTED (空 = 跟批次走)
        [decision_by]       VARCHAR(128) NULL,
        [decision_at]       DATETIME2 NULL,

        -- 後續搬移狀態
        [final_path]        NVARCHAR(512) NULL,          -- 搬到 samba 後的路徑
        [moved_at]          DATETIME2 NULL,

        FOREIGN KEY ([batch_id]) REFERENCES [Batch]([batch_id])
    );

    CREATE INDEX IX_BatchFile_Batch ON [BatchFile] ([batch_id]);
    PRINT N'BatchFile 表建立完成';
END
GO

-- ============================================
-- PortalUser: Portal 使用者紀錄 (從 AD 帶過來的 cache)
-- 不存密碼, 只 cache 顯示名稱與部門
-- ============================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'PortalUser')
BEGIN
    CREATE TABLE [dbo].[PortalUser] (
        [ad_account]        VARCHAR(128) NOT NULL PRIMARY KEY,  -- CORP\wang.manager
        [display_name]      NVARCHAR(128) NULL,                 -- 王主管
        [email]             VARCHAR(256) NULL,
        [department]        NVARCHAR(64) NULL,
        [first_login_at]    DATETIME2 NULL,
        [last_login_at]     DATETIME2 NULL,
        [login_count]       INT NOT NULL DEFAULT 0,
        [is_admin]          BIT NOT NULL DEFAULT 0,             -- IT 管理員
        [is_active]         BIT NOT NULL DEFAULT 1
    );

    CREATE INDEX IX_PortalUser_Email ON [PortalUser] ([email]);
    CREATE INDEX IX_PortalUser_Admin ON [PortalUser] ([is_admin]) WHERE [is_admin] = 1;
    PRINT N'PortalUser 表建立完成';
END
GO

-- ============================================
-- SambaPathHistory: samba 路徑變更歷史 (對應 mockup 編輯頁)
-- ============================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'SambaPathHistory')
BEGIN
    CREATE TABLE [dbo].[SambaPathHistory] (
        [id]                BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        [business_code]     VARCHAR(16) NOT NULL,
        [old_path]          VARCHAR(128) NULL,
        [new_path]          VARCHAR(128) NOT NULL,
        [changed_by]        VARCHAR(128) NOT NULL,
        [changed_at]        DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        [notified_count]    INT NULL,                    -- 通知幾位 OA USER
        [notes]             NVARCHAR(512) NULL
    );

    CREATE INDEX IX_SambaPath_Business ON [SambaPathHistory] ([business_code], [changed_at]);
    PRINT N'SambaPathHistory 表建立完成';
END
GO

-- ============================================
-- View: 跨表查詢 (Portal 稽核查詢頁用)
-- ============================================
IF NOT EXISTS (SELECT * FROM sys.views WHERE name = 'V_AuditLog_Detail')
BEGIN
    EXEC('
    CREATE VIEW [dbo].[V_AuditLog_Detail] AS
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
    FROM [AuditLog] a
    LEFT JOIN [PortalUser] u ON a.actor_user = u.ad_account
    LEFT JOIN [BusinessCode] b ON a.business_code = b.code
    ');
    PRINT N'V_AuditLog_Detail view 建立完成';
END
GO

-- ============================================
-- 初始資料: 4 個示範業務代號
-- ============================================
IF NOT EXISTS (SELECT * FROM [BusinessCode] WHERE code = 'u01')
BEGIN
    INSERT INTO [BusinessCode] (code, name, owner_ad, approver_ad_group, samba_dir, download_ad_group, retention_days, allow_protocols, description)
    VALUES
        ('u01', N'架構科月結報表', 'CORP\zhang.ming',  'g_u01_approvers', 'architecture', 'dept_archi_view',    7, 'SFTP', N'架構科月結資料'),
        ('u02', N'人資考勤資料',  'CORP\lee.dahua',   'g_u02_approvers', 'hr',           'dept_hr_view',       7, 'SFTP', N'HR 月度考勤'),
        ('u03', N'財務沖銷',      'CORP\chen.officer','g_u03_approvers', 'finance',      'dept_finance_view',  7, 'SFTP', N'財務月結沖銷'),
        ('u04', N'資安事件回報',  'CORP\wu.security', 'g_u04_approvers', 'security',     'dept_security_view', 7, 'SFTP+FTPS', N'資安通報');
    PRINT N'初始業務代號 u01~u04 已建立';
END
GO

-- ============================================
-- 設置權限 (給 svc_portal 服務帳號)
-- ============================================
-- 實際部署時, 由部署腳本執行:
-- CREATE LOGIN [SF\svc_portal] FROM WINDOWS;
-- CREATE USER [svc_portal] FOR LOGIN [SF\svc_portal];
-- EXEC sp_addrolemember 'db_datareader', 'svc_portal';
-- EXEC sp_addrolemember 'db_datawriter', 'svc_portal';
-- GRANT EXECUTE TO [svc_portal];

PRINT N'==========================================';
PRINT N' AuditLog Database schema 建立完成';
PRINT N'==========================================';
PRINT N' 表: AuditLog, BusinessCode, Batch, BatchFile, PortalUser, SambaPathHistory';
PRINT N' 視圖: V_AuditLog_Detail';
PRINT N' 初始資料: u01~u04 業務代號';
GO
