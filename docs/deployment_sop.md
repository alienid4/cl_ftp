# SF 部署 SOP (Standard Operating Procedure)

> 目的: 把 SF 主機從空白 Windows Server 部署成可運作的檔案交換平台。
> 對象: IT 維運人員 (照本宣科即可, 無需了解內部細節)。
> 預估時間: **60-90 分鐘** (含 Windows Update + 下載 + 安裝 + 驗證)

---

## 0. 前置條件 (部署前確認)

### 主機準備
- [ ] Windows Server 2022 Standard, 已加入公司 AD 網域
- [ ] 規格: 8 vCPU / 32 GB RAM / C: 200 GB / **D: 1 TB**
- [ ] 主機名稱與 IP 已申請
- [ ] Windows Update 跑完 1 次

### IT / 公司資源
- [ ] **SSL 憑證**: 公司 PKI 核發, 主機 FQDN
- [ ] **AD 群組已建** (建議由 AD admin 處理, 1 個業務代號 2 個群組):
  - `g_u01_approvers` (架構科簽核者) ~ `g_u04_approvers`
  - `dept_archi_view` (架構科可下載者) ~ `dept_security_view`
- [ ] **PAM 系統** 確認接受新增業務代號帳號納管
- [ ] **公司 NTP server** 位址 (例: `ntp1.corp.local`)
- [ ] **公司 SMTP relay** 位址 (例: `mail-relay.corp.local`)
- [ ] **公司備份目標** SMB 路徑 (例: `\\backup-srv\sf-backup`)
- [ ] **防火牆審單** 已通過: 22 / 443 / 445 / 3389 / 1433 / 25 / 123 / 50000-50100

### 工作站準備 (打包用, 不是 SF)
- [ ] 1 台有 **Internet 存取** 的 Windows 工作站
- [ ] 工作站已裝 **Python 3.11+** (給 pip download wheels 用)
- [ ] 工作站有 PowerShell 5.1+

---

## 1. 在外網工作站打包離線 bundle

### 1.1 下載專案

```powershell
# 從 git / 內網檔案伺服器取得 SFTP 專案到工作站
# 或從 USB 拷貝 C:\ClaudeHome\SFTP 整個資料夾
```

### 1.2 跑打包腳本

```powershell
cd C:\ClaudeHome\SFTP\deploy\offline
.\build_offline_bundle.ps1
```

**預期輸出**:
```
=== SF 離線 bundle 建構器 ===
[下載] Visual C++ Redistributable x64 (~25 MB)
[下載] SQL Server 2022 Express (~250 MB)
...
[ok] sf_offline_bundle_YYYYMMDD.zip (~600 MB)
```

### 1.3 拿到 zip 後

```powershell
# 檔案位置
dir .\bundle_output\sf_offline_bundle_*.zip
```

**注意**: 如果某個套件下載失敗, 手動下載後放到 `bundle_output\sf_offline_xxx\installers\`, 重跑 `build_offline_bundle.ps1`。

---

## 2. 帶 bundle 進公司內網

### 選項 A: USB 拷貝 (最常見)
1. zip 拷貝到 USB
2. USB 掃毒
3. 在 SF 主機解壓到 `C:\ClaudeHome\SFTP\`

### 選項 B: 公司安全傳檔通道 (SFTP / 內部檔案伺服器)
1. 用既有的內部檔案傳輸機制
2. SF 主機從共用區拉到本機解壓

### 選項 C: SCCM 軟體分發 (大企業)
1. 將 zip 封裝為 SCCM Package
2. 部署到 SF 主機

---

## 3. 在 SF 主機 — 一鍵安裝

### 3.1 確認解壓位置
```powershell
dir C:\ClaudeHome\SFTP\
# 應該看到: deploy/ scripts/ config/ sql/ docs/ install_offline.ps1
```

### 3.2 以管理員開 PowerShell

開始 → 右鍵 PowerShell → **以系統管理員身分執行**

### 3.3 預演 (建議第一次跑)

```powershell
cd C:\ClaudeHome\SFTP\deploy\offline
.\install_offline.ps1 -DryRun
```

預演會列出所有步驟但不執行, 看一下沒問題再實際跑。

### 3.4 實際安裝

**情境 A — 第一階段** (本機 SQL Express, 推薦從這開始):
```powershell
.\install_offline.ps1
```

**情境 B — 第二階段** (公司 DB 已申請完):
```powershell
.\install_offline.ps1 `
    -DbMode CorpDB `
    -CorpDBServer 'corp-sql01.internal,1433' `
    -CorpDBName 'FileExchangeAudit'
```

**預期輸出 (摘要)**:
```
Step 0: 前置檢查
[ok] 管理員權限
[ok] bundle 結構正常

Step 1: Visual C++ Redistributable
[ok]

Step 2: SQL Server 2022 Express
[ok]

... (省略中間步驟)

Step 9: 執行 deploy/00 ~ 17 設定腳本
→ 執行 00_check_prereqs.ps1
→ 執行 01_setup_directories.ps1
...
→ 執行 17_vuln_scan_hint.md

============================================================
 一鍵安裝完成
============================================================
DB 模式: Express
耗時:    32:15
```

---

## 4. 部署後驗證 (10 個檢查點)

### 4.1 跑健康檢查
```powershell
cd C:\ClaudeHome\SFTP
.\scripts\health_check.ps1
```

**預期**: 全部 `[ OK ]`, 沒有 `[FAIL]`。

### 4.2 SSL 憑證匯入
```powershell
# 把公司 PKI 核發的 .pfx 匯入 LocalMachine\My
Import-PfxCertificate -FilePath 'C:\temp\sf-cert.pfx' `
    -CertStoreLocation Cert:\LocalMachine\My `
    -Password (Read-Host -AsSecureString)

# 拿到 thumbprint
Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -like '*sf.corp.local*' }

# 重跑 06_install_iis.ps1 加上 thumbprint
cd .\deploy
.\06_install_iis.ps1 -CertThumbprint '<thumbprint>'
```

### 4.3 SFTP 測試 (用 WinSCP 從跳板機)
```
主機: <sf-host-ip>
Port: 22
帳號: u01
密碼: (向 PAM 申請)
```
應該登入後在 `inbound/` 目錄看到空白。上傳一個測試檔。

### 4.4 Portal 測試
```
瀏覽器: https://<sf-host-fqdn>/
登入: 您的 AD 個人帳號 (CORP\xxx)
```
看到首頁 + 業務代號 + 可下載清單 (如果是業務負責人或下載者群組)。

### 4.5 簽核流程測試
1. 用 SFTP 上傳 5 個檔到 u01 (秒級內傳完)
2. 等 30 秒 → Portal「我的待簽」應該看到 1 個批次 (5 檔)
3. 點 [全收] → 檔案搬到 `\\SF\architecture\`

### 4.6 SMB 下載測試
```
從 OA 端工作站開檔案總管: \\sf-host\architecture\
```
應該看到剛簽核通過的 5 個檔。Ctrl+A 多選 → 拖到本機。

### 4.7 AuditLog 驗證
```powershell
sqlcmd -S .\SQLEXPRESS -E -d FileExchangeAudit `
    -Q "SELECT TOP 10 event_time, source_system, event_type, actor_user, business_code, target_file, result FROM AuditLog ORDER BY event_time DESC"
```
應該看到「SFTP_UPLOAD → APPROVE_OK → MOVE_OK → SMB_DOWNLOAD」一整條鏈。

### 4.8 排程工作驗證
```powershell
Get-ScheduledTask -TaskName 'SF_*' | Get-ScheduledTaskInfo | Select TaskName, LastRunTime, LastTaskResult
```
應該每個都 `LastTaskResult = 0`。

### 4.9 防火牆規則
```powershell
Get-NetFirewallRule -Name 'FX-*' | Select Name, Enabled, Action
```
應該看到 FX-HTTPS-443-In / FX-SFTP-22-In / FX-RDP-3389-In 都 Enabled = True。

### 4.10 Defender 與 NTP
```powershell
Get-MpComputerStatus | Select RealTimeProtectionEnabled, AntivirusSignatureLastUpdated
& w32tm /query /status
```
應該防護啟用 + NTP 同步 OK。

---

## 5. 上線後 IT 日常維運

### 每日
- 早上開 Portal 看「最近異常事件」(Dashboard)
- 確認 `SF_Monitoring_Check` 沒寄告警

### 每週
- 看 `SF_DailyBackup` 排程結果, 確認備份成功
- 跑 `tail_log.ps1 -ErrorsOnly -Since 10080` (一週) 巡邏

### 每月
- 確認 D: 磁碟 < 80%
- 查看 AuditLog 行數成長率
- 確認 Defender 病毒碼為當週版本
- 跑 `collect_debug_bundle.ps1` 留檔

### 每季
- 跑公司既有 Nessus / OpenVAS 弱掃
- 檢視 PAM 帳號清單, 確認 u0X 都還在用
- 業務代號生命週期: 不再用的停用

### 出問題時
- **故障當下**: `.\scripts\tail_log.ps1` 立刻看 (秒級)
- **要分析 root cause**: `.\scripts\collect_debug_bundle.ps1` 打包 (3 分鐘) → 貼 **GPT Enterprise** 分析
- **服務掛了**: `Restart-Service sshd` / `Restart-Service W3SVC` / `Restart-Service FileExchangePortal`

---

## 6. 第二階段: 切換到公司 DB

確認以下都到位:
- [ ] DBA 提供 DB Server 連線字串
- [ ] DB `FileExchangeAudit` 已建立
- [ ] SF 機器帳號或服務帳號有 `db_owner` 或 `db_datareader + db_datawriter` 權限
- [ ] 防火牆 SF → DB Server TCP 1433 已通

跑遷移:
```powershell
# 預演
cd C:\ClaudeHome\SFTP
.\scripts\migrate_db_to_corp.ps1 -CorpDBServer 'corp-sql01.internal,1433'

# 實際執行
.\scripts\migrate_db_to_corp.ps1 -CorpDBServer 'corp-sql01.internal,1433' -Confirm
```

預期 5-10 分鐘完成, Portal 自動重啟連到新 DB。

---

## 7. 常見問題 FAQ

### Q1: install_offline.ps1 跑到一半某步驟失敗?
A: 腳本是 idempotent (重跑會跳過已完成), 改完問題重跑就好。

### Q2: SQL Express 一直裝不起來?
A: 確認 SSEI 已下載完整版到 `installers/SQLEXPR_x64_ENU.exe`。如果只有 SSEI downloader, 跑 SSEI 一次選 "Download" 抓完整包。

### Q3: pip install 找不到套件?
A: 確認 `python_wheels/` 內有對應 wheel, 且版本符合 Python 3.11 win_amd64。

### Q4: OpenSSH 起不來?
A: 檢查 `sshd_config` 路徑權限 (應該只給 Administrators / SYSTEM 讀寫):
```powershell
icacls C:\ProgramData\ssh\sshd_config /inheritance:r
icacls C:\ProgramData\ssh\sshd_config /grant 'Administrators:F' 'SYSTEM:F'
Restart-Service sshd
```

### Q5: Portal 開不起來?
A:
```powershell
.\scripts\health_check.ps1   # 確認服務狀態
.\scripts\tail_log.ps1 -Source portal -Lines 100   # 看 Portal log
nssm status FileExchangePortal   # 確認 NSSM 起來了
```

### Q6: 簽核通知信沒寄出?
A: 確認 SMTP relay 通:
```powershell
Test-NetConnection -ComputerName mail-relay.corp.local -Port 25
```
不通就找網管查防火牆。

### Q7: 怎麼新增業務代號?
A: Portal 管理員介面 → 業務代號管理 → ➕ 新增業務代號。建立後通知 PAM admin 納管。

### Q8: 公司 DBA 不收我的 DB 申請?
A: Express 永久走也 OK, 10 GB 上限可用 14 年。

---

## 8. 重要連絡人 (需填)

| 角色 | 姓名 | 聯絡 |
|---|---|---|
| 系統 Owner | (填) | (填) |
| IT 管理員 | (填) | (填) |
| AD 管理員 | (填) | (填) |
| DBA | (填) | (填) |
| PAM 管理員 | (填) | (填) |
| 網管 (防火牆) | (填) | (填) |
| 資安 | (填) | (填) |

---

## 9. 變更紀錄

| 版本 | 日期 | 修訂者 | 內容 |
|---|---|---|---|
| 1.0 | 2026-05-18 | IT | 初版 |
