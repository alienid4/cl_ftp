# SF 中繼檔案交換主機 (Windows Server 版本)

> **檔案中繼平台**: SFTP 上傳 + ANY 制簽核 + SMB / Portal ZIP 下載 + 全程稽核留痕
> 對齊主管圖 + Z 方案增值 (OA 端 USER 取檔 / 業務簽核 / Portal 集中視覺化)

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

## 快速開始

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
| [docs/deployment_sop.md](docs/deployment_sop.md) | 部署 SOP |
| [portal/README.md](portal/README.md) | Portal 開發者指引 |

---

## License & Notice

本系統為公司內部資產, 非開源。
所有 log 與業務資料受公司資安政策保護, 不得外流。
