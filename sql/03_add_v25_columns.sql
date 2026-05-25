-- v2.5.0 新增欄位 — 簽核細節頁要顯的補充欄
-- 不重建 DB, 對既有 batch / batchfile 表 ALTER ADD

ALTER TABLE batch
    ADD COLUMN IF NOT EXISTS source_host       VARCHAR(128),
    ADD COLUMN IF NOT EXISTS pam_request_id    VARCHAR(64),
    ADD COLUMN IF NOT EXISTS uploader_name     VARCHAR(128),
    ADD COLUMN IF NOT EXISTS applied_at        TIMESTAMP WITH TIME ZONE,
    ADD COLUMN IF NOT EXISTS purpose_note      VARCHAR(512);

ALTER TABLE batchfile
    ADD COLUMN IF NOT EXISTS mime_type         VARCHAR(64),
    ADD COLUMN IF NOT EXISTS file_ext          VARCHAR(16),
    ADD COLUMN IF NOT EXISTS virus_scan        VARCHAR(16) DEFAULT 'PENDING';

SELECT 'v2.5.0 schema 補欄完成' AS result;
