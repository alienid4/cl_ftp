# SF 中繼檔案交換主機

> **檔案中繼平台**: SFTP 上傳 + ANY 制簽核 + SMB / Portal ZIP 下載 + 全程稽核留痕
> 對齊主管圖 + Z 方案增值 (OA 端 USER 取檔 / 業務簽核 / Portal 集中視覺化)

---

## 雙平台支援 (v1.x = Windows, v2.x = RHEL)

| 主版本 | 平台 | 部署目錄 | 狀態 |
|---|---|---|---|
| **v1.x.x** | Windows Server 2022 | `deploy/`, `scripts/*.ps1` | maintenance |
| **v2.x.x** ⭐ | RHEL 8/9 | `deploy-rhel/`, `config/*linux*` | **主開發** |

新環境**建議用 v2.x (RHEL)** — Linux 用戶速度快 10 倍, 同一份 Flask Portal 程式碼跨平台。

詳見: [v1 → v2 升級決策](docs/runbook/eval_20260520_0900_rhel_alternative.md)

---

## 專案目標

公司部門間 / 系統間 / 人員間的檔案交換, **單一窗口**、**最小權限**、**全程留痕**、**可重現查詢**。

| 角色 | 動作 |
|---|---|
| PRD 端 AP 主機 | SFTP / FTPS 上傳到 SF 業務代號帳號 u0X |
| 業務主管 (5 人) | Portal ANY 制簽核, 任 1 同意即放行 |
| OA 端 USER | SMB 掛載 / Portal 批次 ZIP 下載 |
| IT 管理員 | Portal 管理業務代號 / 全公司稽核查詢 / 系統健康 |

---

## 快速開始 (v2.x / RHEL 推薦) ⭐

```bash
sudo dnf install -y git
cd /opt
sudo git clone https://github.com/alienid4/cl_ftp sf
cd sf
sudo ./deploy-rhel/install_all.sh
```

完成後自動顯示訪問網址。詳見 [v2.0.0 部署 SOP](docs/runbook/v2.0.0_20260520_1100_first_deploy.md)。

---

## 快速開始 (v1.x / Windows, maintenance)

### 1. 外網工作站 — 打包離線 bundle (~600 MB)
```powershell
cd C:\ClaudeHome\SFTP\deploy\offline
.\build_offline_bundle.ps1
```

### 2. SF 主機 — 一鍵安裝
```powershell
# 第一階段 (SQL Express 本機)
.\install_offline.ps1

# 第二階段 (公司 DB)
.\install_offline.ps1 -DbMode CorpDB -CorpDBServer 'corp-sql01.internal,1433'
```

### 3. 驗證
```powershell
.\scripts\health_check.ps1
.\scripts\tail_log.ps1
```

詳見 [docs/deployment_sop.md](docs/deployment_sop.md)

---

## 檔案結構

```
SFTP/
├── README.md                   ← 本檔
├── deploy/                     ← 18 支部署腳本 (00~17)
│   └── offline/                ← 離線打包與一鍵安裝
├── scripts/                    ← 維運腳本 (tail_log / health_check / debug_bundle / migrate_db)
├── config/                     ← sshd_config / web.config / banner.txt
├── sql/                        ← AuditLog Schema
├── portal/                     ← Flask Portal 程式碼
└── docs/                       ← 架構圖 / mockup / 文件
    ├── architecture-v2.html        Z 方案完整版架構圖
    ├── mockup-user.html            一般使用者介面
    ├── mockup-admin.html           管理員介面
    ├── required_packages.md        套件清單
    └── deployment_sop.md           部署 SOP
```

---

## 設計核心

| 項目 | 決定 |
|---|---|
| 上傳通道 | SFTP (主) / FTPS (備案, 預設停用) |
| 下載通道 | SFTP (給機器) / SMB (給人) / Portal ZIP (給不會 SMB 的人) |
| 帳號模型 | u0X 業務代號 (PAM 納管) + AD 個人帳號 (Portal/SMB) |
| 簽核制度 | 5 人 ANY 制, AD 群組自助維護 |
| 批次聚合 | 滑動 30 秒 + 5 分鐘安全閥, 1 行 1 批可展開細選 |
| 保留期 | u0X home 7 天 + samba 7 天 + AuditLog 線上 365 天 + 歸檔 5 年 |
| DB | 第一階段 SQL Express, 第二階段可遷移公司 MS SQL Server |
| Log | AuditLog 預留 CEF/syslog 欄位, 階段二接 SIEM |

詳見 [plan 檔](../../Users/leea6/.claude/plans/windows-server-indexed-turing.md)

---

## 相關文件

| 文件 | 用途 |
|---|---|
| [plans/windows-server-indexed-turing.md](../../Users/leea6/.claude/plans/windows-server-indexed-turing.md) | 完整設計 plan |
| [docs/architecture-v2.html](docs/architecture-v2.html) | Z 方案架構圖 |
| [docs/mockup-user.html](docs/mockup-user.html) | 使用者介面 mockup |
| [docs/mockup-admin.html](docs/mockup-admin.html) | 管理員介面 mockup |
| [docs/required_packages.md](docs/required_packages.md) | 套件清單 |
| [docs/deployment_sop.md](docs/deployment_sop.md) | 部署 SOP (準備階段 + 套件安裝) |
| [docs/startup_sop.md](docs/startup_sop.md) | **🚀 啟動 SOP** (install 跑完後 8 步, 從套件就緒到第一個檔案流過) |
| [portal/README.md](portal/README.md) | Portal 開發者指引 |
| [patches/README.md](patches/README.md) | **Patch 管理規範 + 版本歷史** |
| [docs/known_issues.md](docs/known_issues.md) | 已知問題 + 解法 (8 個常見坑) |
| [docs/dev-log/](docs/dev-log/) | **開發者紀錄** (規範 / 錯誤追蹤 / 工作日誌) |
| [docs/dev-log/issues_log.md](docs/dev-log/issues_log.md) | 錯誤追蹤紀錄 (9 筆) |
| [docs/dev-log/dev_journal.md](docs/dev-log/dev_journal.md) | 開發者工作日誌 |
| [docs/dev-log/skill_sf_workflow.md](docs/dev-log/skill_sf_workflow.md) | **SKILL 工作流程紀律** (8 大鐵律) |

---

## 📢 免責聲明 / Disclaimer

本專案為**公開的參考實作 (reference implementation)**, 用於展示 Windows Server 上建置中繼檔案交換主機的設計與部署方式。

- 所有業務代號 (u01~u04)、部門名稱、人員姓名、IP 位址、AD 群組名稱**均為示範值**, 不對應任何真實組織。
- 設計取材自業界常見的金融業 / 企業內網檔案交換場景, **非任何特定公司的實際系統**。
- 部署到正式環境前, 請依貴公司資安政策 / 命名規範 / 認證方式 自行客製。
- 開發者不保證本程式碼在所有環境下的安全性或可用性。

This is a public **reference implementation** demonstrating how to build a relay file exchange server on Windows Server. All business codes, department names, user names, IP addresses, and AD group names are **placeholder examples** and do not correspond to any real organization. Adapt to your own corporate policies before production deployment.
