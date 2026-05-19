# SF 安裝後啟動 SOP

`install_offline.ps1` 跑完後, **套件裝好但服務還沒就緒**。本文件帶您走完從「套件裝完」到「第一個檔案成功流過 SF」的 8 步。

預估時間: **60-90 分鐘** (含 AD/PAM/DBA 協調等待)。

---

## Step 0: 先確認 install 真的跑完

```powershell
cd C:\ClaudeHome\SFTP
.\scripts\health_check.ps1
```

預期看到 (摘要):
```
[ OK ]  Service: sshd                          OpenSSH SFTP: Running
[ OK ]  Service: W3SVC                         IIS Web Server: Running
[ OK ]  Service: MSSQL$SQLEXPRESS              SQL Server Express: Running
[ OK ]  Service: LanmanServer                  SMB Server: Running
[ OK ]  Service: W32Time                       NTP 時間同步: Running
[ OK ]  Service: WinDefend                     Defender: Running
[ OK ]  D: 磁碟使用率                          XX% 已用, 剩 XXX GB
[ OK ]  記憶體使用率                          XX% / XX GB
[ OK ]  NTP 同步                              Source: <ntp-server>
```

→ 有 `[FAIL]` 就先處理 (大概是 SSL 憑證未匯入導致 IIS 起不來, 詳見 Step 1)。

---

## Step 1: 匯入 SSL 憑證 + 綁定 IIS HTTPS 443

### 1.1 取得憑證

從公司 PKI / 資安部取得 `.pfx` 檔 (含私鑰), CN 必須是 SF 主機 FQDN (例如 `sf-01.corp.local`)。

### 1.2 匯入到 Local Machine

```powershell
$pfxPath = 'C:\Temp\sf-cert.pfx'
$pwd = Read-Host -AsSecureString -Prompt "PFX 密碼"

Import-PfxCertificate -FilePath $pfxPath `
    -CertStoreLocation Cert:\LocalMachine\My `
    -Password $pwd

# 拿到 thumbprint
Get-ChildItem Cert:\LocalMachine\My |
    Where-Object { $_.Subject -like '*sf-01*' } |
    Select-Object Subject, Thumbprint
```

### 1.3 綁定到 IIS Site

```powershell
# 帶 thumbprint 重跑 06_install_iis.ps1
cd .\deploy
.\06_install_iis.ps1 -CertThumbprint '<貼上 thumbprint>' -HostName 'sf-01.corp.local'

# 或手動綁:
Import-Module WebAdministration
$binding = Get-WebBinding -Name 'FileExchangePortal' -Protocol https
$binding.AddSslCertificate('<thumbprint>', 'My')

iisreset
```

### 1.4 驗證

```powershell
# 開瀏覽器 (從跳板機, 不從 SF 本機)
Start-Process 'https://sf-01.corp.local/'
```

應該看到 Portal 登入頁 (或 404 / 連線錯誤, 看 Portal 是否已啟動, 見 Step 7)。

---

## Step 2: 建立業務代號 u01~u04 帳號 (Local + 加群組)

### 2.1 跑 04 腳本互動式建立

```powershell
cd .\deploy
.\04_create_sftp_accounts.ps1 -Departments @('u01','u02','u03','u04')
```

會依序提示輸入 4 個帳號的初始密碼 (>= 14 碼, 含複雜度)。**先用臨時密碼**, 之後 PAM 接管會自動 rotate (Step 4)。

### 2.2 確認帳號狀態

```powershell
Get-LocalUser -Name 'u0*' | Format-Table Name, Enabled, PasswordExpires
Get-LocalGroupMember -Group 'sftp_users'
```

預期看到 u01~u04 都 Enabled, 都在 sftp_users 群組。

---

## Step 3: 建立 AD 群組 (請 AD admin 做)

向公司 AD 管理員提申請, 建立**至少 8 個群組** (每個業務代號 2 個):

| 群組名 | 用途 | 初始成員 |
|---|---|---|
| `g_u01_approvers` | u01 業務簽核者 (5 人 ANY 制) | 5 位主管 |
| `g_u02_approvers` | u02 簽核 | 5 位 |
| `g_u03_approvers` | u03 簽核 | 5 位 |
| `g_u04_approvers` | u04 簽核 | 5 位 |
| `dept_<u01-dir>_view` | u01 對應部門 SMB 下載者 | 該部門 ~20 位 |
| `dept_<u02-dir>_view` | u02 部門下載 | ~20 位 |
| `dept_<u03-dir>_view` | u03 部門下載 | ~20 位 |
| `dept_<u04-dir>_view` | u04 部門下載 | ~20 位 |

→ **沒這個就跑不起來**, AD 是 SF 的認證基礎。

驗證 (在 SF 主機):
```powershell
Import-Module ActiveDirectory
Get-ADGroup -Filter 'Name -like "g_u0*_approvers"' | Select-Object Name
Get-ADGroup -Filter 'Name -like "dept_*_view"' | Select-Object Name
```

---

## Step 4: 通知 PAM 管理員納管 u01~u04

向 PAM 管理員提**納管申請**, 內容:

```
申請項目: SF 主機本機帳號納管
主機名:   sf-01.corp.local
帳號:     u01, u02, u03, u04
納管方式: 密碼揭露模式 (使用者向 PAM 申請 → 取得當前密碼 → 在 AP 主機跑 sftp)
密碼 rotate: 取用後 24 小時 (或您公司 PAM 政策)
SF 端配合: 已開好 svc_pam 服務帳號, 給 "Reset Password for u0X" 權限
```

PAM 管理員會把 SF 上 u01~u04 拉進 PAM 金庫, 之後密碼由 PAM 控管。

驗證 (向 PAM 申請 u01 密碼, 取到才算成功):
```
登入 PAM Portal → 申請 u01 → 顯示當前密碼 → 複製
```

---

## Step 5: 建立 AuditLog DB Schema

### 5.1 確認 SQL Express 啟動

```powershell
Get-Service 'MSSQL$SQLEXPRESS' | Select-Object Name, Status
```

### 5.2 跑 schema 腳本

```powershell
cd C:\ClaudeHome\SFTP\sql
sqlcmd -S .\SQLEXPRESS -E -i .\01_create_db.sql
```

預期看到:
```
Changed database context to 'master'.
Database 'FileExchangeAudit' created.
... (CREATE TABLE 等)
```

### 5.3 驗證

```powershell
sqlcmd -S .\SQLEXPRESS -E -d FileExchangeAudit -Q "SELECT name FROM sys.tables"
```

應該列出:
- AuditLog
- Batch
- BatchFile
- BusinessCode
- PortalUser
- SambaPathHistory
- (其他)

---

## Step 6: 設定 SMB Share (對應業務代號)

### 6.1 建立 share + ACL

每個業務代號對應一個 SMB share:

```powershell
# 例: u01 對應架構科 (假設 dir 名 = architecture)
$dept = 'architecture'
$adGroup = 'CORP\dept_architecture_view'   # 對應 AD 群組

$path = "D:\DataExchange\samba\$dept"
New-Item -Path $path -ItemType Directory -Force | Out-Null

# 建 SMB share
New-SmbShare -Name $dept -Path $path -ReadAccess $adGroup `
    -Description "SF 檔案交換 - $dept 部門下載區"

# NTFS ACL (給 AD 群組讀取)
icacls $path /grant "${adGroup}:(OI)(CI)RX"

# SACL 稽核 (記錄所有存取)
$sacl = Get-Acl $path -Audit
$auditRule = New-Object System.Security.AccessControl.FileSystemAuditRule(
    'Everyone', 'ReadAndExecute', 'ContainerInherit,ObjectInherit', 'None', 'Success,Failure')
$sacl.AddAuditRule($auditRule)
Set-Acl $path -AclObject $sacl
```

→ 4 個業務代號做完, 應該有 4 個 SMB share。

### 6.2 驗證

```powershell
Get-SmbShare | Where-Object { $_.Path -like '*samba*' }
```

---

## Step 7: 啟動 Portal (NSSM 註冊 + Start-Service)

### 7.1 註冊 Portal Service

```powershell
# 假設 NSSM 已解壓到 C:\Tools\nssm.exe
$nssm = 'C:\Tools\nssm.exe'

# 註冊 Flask Portal 為 Windows Service
& $nssm install FileExchangePortal `
    "D:\_portal\app\.venv\Scripts\python.exe" `
    "D:\_portal\app\wsgi.py"

& $nssm set FileExchangePortal AppDirectory 'D:\_portal\app'
& $nssm set FileExchangePortal Start SERVICE_AUTO_START
& $nssm set FileExchangePortal AppStdout 'D:\_portal\logs\portal-stdout.log'
& $nssm set FileExchangePortal AppStderr 'D:\_portal\logs\portal-stderr.log'

# 設執行身分 (svc_portal 服務帳號)
$svcUser = 'NT AUTHORITY\NetworkService'   # 或 svc_portal
& $nssm set FileExchangePortal ObjectName $svcUser
```

### 7.2 啟動

```powershell
Start-Service FileExchangePortal
Get-Service FileExchangePortal
```

預期 Status: Running。

### 7.3 驗證

```powershell
# 內部測試 (從 SF 本機, 跳過 IIS reverse proxy)
Invoke-WebRequest http://127.0.0.1:5000/api/health -UseBasicParsing | Select-Object StatusCode, Content
```

預期: `200`, JSON `{"service":"sf-portal","status":"ok","db":"ok",...}`

### 7.4 從外部驗證

```powershell
# 從跳板機開瀏覽器
Start-Process 'https://sf-01.corp.local/'
```

應該看到登入頁, 用 AD 帳號登入。

---

## Step 8: 煙霧測試 (端到端跑一次)

### 8.1 IT 在 Portal 加業務代號 u01

1. 用 IT admin AD 帳號登入 Portal
2. 進「業務代號管理」→ 新增
3. 填:
   - 代號: `u01`
   - 名稱: `<業務名稱>`
   - 負責人 AD: `<某主管 AD 帳號>`
   - 簽核 AD 群組: `g_u01_approvers`
   - samba 目錄: `architecture`
   - 下載 AD 群組: `dept_architecture_view`
   - 保留期: 7 天

### 8.2 在 AP 主機跑 SFTP 上傳

```powershell
# 在 AP 主機 (PRD 網段, 已用 AP01 登入)
# 1. 向 PAM 申請 u01 密碼
# 2. 跑 sftp
sftp u01@sf-01.corp.local
# 輸入密碼 (剛從 PAM 取得)
sftp> put test-file.txt
sftp> quit
```

### 8.3 確認 Portal 收到批次

簽核者 (g_u01_approvers 成員) 登入 Portal:
- 「我的待簽列表」應該看到 1 個批次 (滑動 30 秒聚合後)
- 點「全收」

### 8.4 OA 端 USER 下載

OA 端 USER (dept_architecture_view 成員):
```
檔案總管打: \\sf-01.corp.local\architecture
應該看到 test-file.txt
拖到本機 → 完成下載
```

### 8.5 確認 AuditLog 全鏈

```powershell
sqlcmd -S .\SQLEXPRESS -E -d FileExchangeAudit -Q `
    "SELECT TOP 20 event_time, source_system, event_type, actor_user, target_file, result FROM AuditLog ORDER BY event_time DESC"
```

應該看到一整條鏈:
```
SFTP    SFTP_UPLOAD       u01 (X via PAM)     test-file.txt   SUCCESS
PORTAL  BATCH_PENDING     (system)            -               SUCCESS
PORTAL  APPROVE_OK        CORP\<approver>     test-file.txt   SUCCESS
PORTAL  MOVE_OK           svc_portal          test-file.txt   SUCCESS
SMB     SMB_DOWNLOAD      CORP\<user>         test-file.txt   SUCCESS
```

---

## ✅ 至此 SF 正式上線

恭喜! 完成這 8 步, 您有:
- ✅ HTTPS Portal 可登入
- ✅ SFTP 接收 u01~u04 上傳
- ✅ Portal ANY 制簽核
- ✅ SMB 給 OA 端下載
- ✅ AuditLog 全鏈記錄
- ✅ PAM 控管 SFTP 密碼

---

## 啟動後常駐動作

### 每天
- 開 Portal Dashboard 看「今日異常事件」
- 確認 `SF_Monitoring_Check` 排程沒寄告警

### 每週
- 看 `SF_DailyBackup` 排程備份成功
- 跑 `tail_log.ps1 -ErrorsOnly -Since 10080` 巡邏一週

### 每月
- 確認 D: 磁碟 < 80%
- 跑 `collect_debug_bundle.ps1` 留檔
- AuditLog 行數成長率

### 每季
- 公司既有 Nessus / OpenVAS 弱掃
- 檢視 PAM 帳號清單, 不用的停用

---

## 出問題怎麼辦?

| 情境 | 看哪 |
|---|---|
| 服務掛了 | `Restart-Service sshd / W3SVC / FileExchangePortal` |
| 故障當下要 log | `.\scripts\tail_log.ps1 -ErrorsOnly` (秒級) |
| 要分析 root cause | `.\scripts\collect_debug_bundle.ps1` (打包送 GPT Enterprise) |
| 健康全檢 | `.\scripts\health_check.ps1` |
| 看歷史問題 | [docs/dev-log/issues_log.md](dev-log/issues_log.md) |
| 找 patch | [patches/](../patches/) |

---

## 將來新業務代號 (例如要加 u05)

1. Portal「業務代號管理」→ 新增 u05
2. SF 主機跑:
   ```powershell
   .\deploy\04_create_sftp_accounts.ps1 -Departments @('u05')
   ```
3. AD admin 建群組: `g_u05_approvers`, `dept_<x>_view`
4. SMB share 建立 (跑 Step 6 的指令, 改成 u05)
5. 通知 PAM 納管 u05

→ 5 分鐘搞定一個新業務代號。

---

## 第二階段: 切換到公司 DB

確認 DBA 給了 instance 後:
```powershell
.\scripts\migrate_db_to_corp.ps1 -CorpDBServer 'corp-sql01.internal,1433' -Confirm
```

詳見 [migrate_db_to_corp.ps1](../scripts/migrate_db_to_corp.ps1) 說明。
