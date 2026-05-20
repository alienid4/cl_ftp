# v2.0.0 — 平台大改版: Windows Server → RHEL 8/9

| 項目 | 內容 |
|---|---|
| **版本** | v2.0.0 |
| **發布日期** | 2026-05-20 |
| **類型** | 主版號升級 (架構變更, 不向下相容) |
| **狀態** | ⭐ **新主分支** (Windows v1.x 保留為 maintenance) |

---

## 為什麼是 v2.0.0 (不是 v1.0.0.11)

依 `patches/README.md` 版本號規則:
> - `v1.0.0.X` 第一個 patch (例如修路徑、改編碼)
> - `v1.1.0` 中型改版 (新增功能, 例如新模組)
> - **`v2.0.0` 大型改版 (架構變更, 不向下相容)** ← 本次

從 **Windows Server 2022 → RHEL 8/9**:
- 不同 OS → 不向下相容
- 整套部署腳本重寫 (ps1 → bash)
- 不同 Web server (IIS → nginx)
- 不同 DB (SQL Express → PostgreSQL)
- 不同 Service manager (NSSM → systemd)
- 不同 AD 整合方式 (Domain Join GUI → realm join)

✅ 完全符合 `v2.0.0` 「大型改版, 不向下相容」定義。

---

## 為什麼改 RHEL (背景)

使用者背景: Linux, 不熟 Windows。v1.x 部署過程暴露多個 Windows 學習成本問題:
- PowerShell 5.1 語法陷阱 (`?.Source`, `Add(Join-Path...)` 等)
- NSSM 註冊 service 卡關
- IIS + URL Rewrite + ARR 三層複雜
- Python wheels 在 Windows 用 user-only 安裝路徑問題
- sshd_config Subsystem 路徑問題 (FoD vs portable 差異)
- SQL Server FILENAME D:\_portal\db\ 路徑寫死問題

→ 預計 Windows 部署完成: 1-2 週
→ 預計 RHEL 部署完成: 6-7 天

效率差 50%+, 改用 RHEL 對使用者效益最大。

決策過程: 見 [eval_20260520_0900_rhel_alternative.md](../../docs/runbook/eval_20260520_0900_rhel_alternative.md)

---

## 雙分支策略

```
main branch
├── v1.0.0 ~ v1.0.0.10   # Windows Server 2022 (maintenance)
└── v2.0.0+              # RHEL 8/9 (主開發) ⭐
```

兩條分支**並存於 main**, 不分 git branch (因為部分東西共用):

| 共用 | Windows-only (v1.x) | RHEL-only (v2.x) |
|---|---|---|
| `portal/` Flask app | `deploy/` (ps1) | `deploy-rhel/` (sh) |
| `sql/01_create_db.sql` (SQL Server) | `scripts/*.ps1` | `config/sshd_config_linux` |
| 規畫文件 | `config/sshd_config` | `config/nginx/` |
| 主管圖 | `release-zip/sf-patch-v1.*.zip` | `config/sssd/` |
| `docs/` (大部分) | | `config/samba/` |
| `docs/runbook/v1.0.0.*` (Windows SOP) | | `sql/01_create_db_postgres.sql` |
| | | `docs/runbook/v2.*` (RHEL SOP) |

---

## v2.0.0 包含什麼

### 新增 24 個檔

#### `deploy-rhel/` — 16 個 bash 腳本
- `install_all.sh` (一鍵)
- `00_check_prereqs.sh` ~ `14_setup_monitoring.sh`
- `health_check.sh`

#### `config/` — 4 個設定檔
- `config/sshd_config_linux` (OpenSSH)
- `config/nginx/sf-portal.conf` (反向代理)
- `config/sssd/sssd.conf` (AD 整合)
- `config/samba/smb.conf` (SMB share)

#### `sql/` — 1 個 schema
- `sql/01_create_db_postgres.sql`

#### `docs/runbook/` — 2 個 runbook
- `v2.0.0_20260520_1100_first_deploy.md` (首次部署 SOP)
- `eval_20260520_0900_rhel_alternative.md` (決策過程)

#### `docs/LINUX_USER_GUIDE.md`
- Linux ↔ Windows 完整對照速查

---

## 對應 v1.x 各檔 (映射表)

| Windows (v1.x) | RHEL (v2.x) | 註 |
|---|---|---|
| `deploy/00_check_prereqs.ps1` | `deploy-rhel/00_check_prereqs.sh` | |
| `deploy/01_setup_directories.ps1` | `deploy-rhel/01_setup_directories.sh` | |
| `deploy/02_setup_ntfs_acl.ps1` | `deploy-rhel/02_setup_ownership.sh` | chown + setfacl |
| `deploy/03_install_openssh.ps1` | `deploy-rhel/03_install_openssh.sh` | RHEL 原生 |
| `deploy/04_create_sftp_accounts.ps1` | `deploy-rhel/04_create_sftp_accounts.sh` | useradd |
| `deploy/05_setup_firewall.ps1` | `deploy-rhel/05_setup_firewall.sh` | firewalld |
| `deploy/06_install_iis.ps1` | `deploy-rhel/06_install_nginx.sh` | **nginx 取代 IIS** |
| `deploy/07_setup_gpo_policy.ps1` | (合併進 03 + 07) | |
| `deploy/08_install_sqlexpress_notes.ps1` | `deploy-rhel/08_setup_postgresql.sh` | **PostgreSQL 取代 SQL Express** |
| `deploy/09_setup_portal.ps1` | `deploy-rhel/09_deploy_portal.sh` | **systemd 取代 NSSM** |
| `deploy/10_setup_ntp.ps1` | `deploy-rhel/10_setup_chrony.sh` | chrony 取代 W32Time |
| `deploy/11_setup_firewall_log.ps1` | `deploy-rhel/12_setup_logging.sh` | auditd + rsyslog |
| `deploy/12_install_ftps.ps1` | (vsftpd, 之後做) | 備案先 skip |
| `deploy/13_setup_defender.ps1` | (ClamAV / 公司 EDR) | 之後做 |
| `deploy/14_setup_quota_fsrm.ps1` | (XFS quota, 之後做) | 之後做 |
| `deploy/15_setup_backup.ps1` | `deploy-rhel/13_setup_backup.sh` | rsync + cron |
| `deploy/16_setup_monitoring.ps1` | `deploy-rhel/14_setup_monitoring.sh` | sar + mail |
| `deploy/offline/install_offline.ps1` | `deploy-rhel/install_all.sh` | bash 一鍵 |
| `scripts/health_check.ps1` | `deploy-rhel/health_check.sh` | bash 速查 |
| (Windows 加入網域 GUI) | `deploy-rhel/07_join_ad.sh` | realm join |
| (內建 SMB Server) | `deploy-rhel/11_setup_samba.sh` | Samba 4 |

---

## v1.x 還留著嗎

**留著**, 但**狀態 = maintenance**:
- 已部署 Windows 主機可繼續用 v1.0.0.10 + 之前的 patches
- 不再加新功能
- 只修 critical bug (例: 安全漏洞)
- 之後標記 `[maintenance]` 狀態

---

## 套用方式 (新環境)

### 全新 RHEL VM

```bash
sudo dnf install -y git
cd /opt
sudo git clone https://github.com/alienid4/cl_ftp sf
cd sf
sudo ./deploy-rhel/install_all.sh
```

詳見 [v2.0.0_20260520_1100_first_deploy.md](../../docs/runbook/v2.0.0_20260520_1100_first_deploy.md)

### 從 Windows v1.x 遷移 (DB 資料)

如果要保留 v1.x 累積的 AuditLog 資料:

```bash
# Windows 主機 (v1.x):
# 匯出 SQL Server AuditLog
SQLCMD -S .\SQLEXPRESS -E -d FileExchangeAudit -Q "SELECT * FROM AuditLog" -o audit.csv

# 拷到 RHEL 主機, 匯入 Postgres
psql -U portal -d file_exchange_audit \
    -c "\copy audit_log FROM 'audit.csv' WITH (FORMAT csv, HEADER true)"
```

---

## 升級到 v2.0.0 的注意

| 項目 | 注意 |
|---|---|
| **OS** | 全新 RHEL 8/9 VM, 不能就地升級 Windows |
| **資料** | 必須先匯出 (SQL Server → CSV → Postgres) |
| **AD 帳號** | 同 AD domain, 帳號可繼續用 |
| **AP 系統** | SFTP client 設定不變 (還是 sftp_hr@<host>) |
| **OA USER** | SMB 訪問位址不變 (\\<host>\<share>) |

---

## 將來 v2.x patch 規劃

| 預計版號 | 內容 |
|---|---|
| `v2.0.0.1` | RHEL 部署 round 1 bug fix (如果有) |
| `v2.0.0.X` | 累積小修補 |
| `v2.1.0` | PAM 整合 (公司 PAM agent for Linux) |
| `v2.2.0` | SIEM forward (rsyslog → 公司 SIEM) |
| `v2.3.0` | AI Agent Runtime 整合 |

---

## 相關連結

- 決策過程: [eval_20260520_0900_rhel_alternative.md](../../docs/runbook/eval_20260520_0900_rhel_alternative.md)
- 部署 SOP: [v2.0.0_20260520_1100_first_deploy.md](../../docs/runbook/v2.0.0_20260520_1100_first_deploy.md)
- Linux 速查: [LINUX_USER_GUIDE.md](../../docs/LINUX_USER_GUIDE.md)
- v1.x 最後一版: [v1.0.0.10 PATCH_NOTE](../v1.0.0.10/PATCH_NOTE.md)
