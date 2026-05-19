# SF (Windows Server) 必裝套件清單

主機目標: Windows Server 2022 Standard, 加入 AD 網域。
分類: **必裝** / **選裝** / **階段二**。

---

## 一、Windows 角色與功能 (Install-WindowsFeature / Add-WindowsCapability)

| 套件 | 必/選 | 用途 | 安裝指令 |
|---|---|---|---|
| **OpenSSH.Server** | 必 | SFTP 主服務 | `Add-WindowsCapability -Online -Name 'OpenSSH.Server~~~~0.0.1.0'` |
| **Web-Server** (IIS) | 必 | Portal 容器 + HTTPS | `Install-WindowsFeature -Name Web-Server -IncludeManagementTools` |
| **Web-Ftp-Server** | 必 (備案) | FTPS 備案 | `Install-WindowsFeature -Name Web-Ftp-Server -IncludeAllSubFeature` |
| **FS-Resource-Manager** | 必 | FSRM 部門配額 | `Install-WindowsFeature -Name FS-Resource-Manager -IncludeManagementTools` |
| **Windows-Server-Backup** | 必 | 資料備份排程 | `Install-WindowsFeature -Name Windows-Server-Backup -IncludeManagementTools` |
| **RSAT-AD-PowerShell** | 必 | Portal 後台改 AD 群組 | `Install-WindowsFeature -Name RSAT-AD-PowerShell` |
| **Web-Http-Logging / Web-Custom-Logging** | 必 | IIS log | (由 06_install_iis.ps1 自動處理) |
| **NET-Framework-45-Features** | 必 | .NET 4.8 相依 | (內建, 確認啟用) |

---

## 二、Microsoft 產品 (下載安裝)

| 套件 | 必/選 | 版本 | 用途 | 下載 |
|---|---|---|---|---|
| **SQL Server 2022 Express** | 必 | 2022 (16.x) | AuditLog DB | https://www.microsoft.com/sql-server/sql-server-downloads |
| **SQL Server Command Line Utilities** | 必 | 18+ | `sqlcmd.exe`, 部署腳本用 | https://learn.microsoft.com/sql/tools/sqlcmd-utility |
| **SQL Server Management Studio (SSMS)** | 選 | 19+ | DB GUI 管理 (IT 用) | https://learn.microsoft.com/sql/ssms/download |
| **.NET Framework 4.8** | 必 | 4.8+ | IIS + 部分模組相依 | (Server 2022 內建) |
| **URL Rewrite Module** | 必 | 2.1+ | IIS → Flask Portal 反向代理 | https://www.iis.net/downloads/microsoft/url-rewrite |
| **Application Request Routing (ARR)** | 必 | 3.0+ | URL Rewrite 配合, 反向代理 | https://www.iis.net/downloads/microsoft/application-request-routing |
| **Visual C++ Redistributable** | 必 | 2015-2022 | SQL Express 與 Python 相依 | https://learn.microsoft.com/cpp/windows/latest-supported-vc-redist |

---

## 三、第三方軟體 (下載安裝)

| 套件 | 必/選 | 版本 | 用途 | 下載 |
|---|---|---|---|---|
| **Python** | 必 | 3.11+ | Flask Portal 執行 | https://www.python.org/downloads/windows/ |
| **NSSM** | 必 | 2.24+ | 把 waitress (Flask) 註冊為 Windows Service | https://nssm.cc/ |
| **Notepad++ / VSCode** | 選 | latest | IT 看 log / 編設定檔 | https://notepad-plus-plus.org/ |
| **Process Explorer (Sysinternals)** | 選 | latest | 進階診斷 | https://learn.microsoft.com/sysinternals/downloads/process-explorer |
| **PuTTY / WinSCP** | 選 | latest | 測試 SFTP 連線 | https://winscp.net/ |
| **FileZilla** | 選 | latest | 測試 FTPS 連線 | https://filezilla-project.org/ |

---

## 四、Python 套件 (pip install)

放在 Portal 虛擬環境 (`D:\_portal\app\.venv\`) 內。寫進 `requirements.txt`:

```txt
# Web framework
flask>=3.0
waitress>=3.0           # Windows-friendly WSGI server (替代 gunicorn)

# DB
pyodbc>=5.0             # SQL Server 連線

# AD / LDAP
ldap3>=2.9              # AD 查群組成員、改 AD 群組
# python-ldap (替代, 但 Windows 編譯較麻煩)

# Auth
flask-login>=0.6
flask-session>=0.5

# Templates / Forms
jinja2>=3.1
flask-wtf>=1.2

# Config
python-dotenv>=1.0
pyyaml>=6.0

# Scheduling
apscheduler>=3.10       # 批次聚合 / 簽核超時 / 7 天清理

# Mail (內建 smtplib, 但用這個更方便)
flask-mail>=0.10

# Utilities
pywin32>=306            # Windows API (建立 AD group, NTFS ACL)
psutil>=5.9             # 系統資源監控
requests>=2.31          # 對外 API (PAM webhook 階段二)

# Excel (匯出稽核報表)
openpyxl>=3.1

# Crypto
cryptography>=42        # TLS, 雜湊
```

---

## 五、PowerShell 模組

| 模組 | 必/選 | 來源 | 用途 |
|---|---|---|---|
| **WebAdministration** | 必 | 內建 (IIS 安裝後) | 部署腳本管理 IIS |
| **NetSecurity** | 必 | 內建 | 防火牆規則 |
| **NetTCPIP** | 必 | 內建 | 網路設定 |
| **FileServerResourceManager** | 必 | FSRM 安裝後 | 配額 |
| **ScheduledTasks** | 必 | 內建 | 排程工作 |
| **ActiveDirectory** | 必 | RSAT-AD-PowerShell | AD 群組操作 |
| **SQLServer** | 選 | `Install-Module SQLServer` | DB 操作 (Invoke-Sqlcmd) |
| **PSWindowsUpdate** | 選 | `Install-Module PSWindowsUpdate` | 自動化 Windows Update |

---

## 六、憑證 (不算「套件」但要備)

| 項目 | 必/選 | 用途 | 取得方式 |
|---|---|---|---|
| **SSL/TLS 憑證** | 必 | IIS HTTPS 443 + FTPS TLS | 公司 PKI 或外部 CA |
| **Service Account (svc_portal)** | 必 | IIS AppPool 身分 | 本機帳號 + 給最小權限 |
| **Service Account (svc_pam)** | 必 | PAM 改 u0X 密碼用 | 本機帳號 + Reset Password 權限 |

---

## 七、外部依賴 (主機外)

| 項目 | 必/選 | 用途 |
|---|---|---|
| **公司 NTP Server** | 必 | 時間同步 (10_setup_ntp.ps1 用) |
| **公司 SMTP Relay** | 必 | Portal 寄通知信 + 監控告警 |
| **AD Domain Controller** | 必 | 帳號認證 |
| **PAM 系統 (客製)** | 必 | u0X 密碼納管 |
| **異地備份目標 (SMB Share)** | 必 | 15_setup_backup.ps1 |
| **公司 Cert Authority (PKI)** | 必 | SSL 憑證 |
| **SIEM 平台** | 階段二 | Log 集中, 階段二接 |
| **Nessus / OpenVAS** | 選 | 弱掃 (公司既有平台) |

---

## 八、階段二 (未來才安裝)

| 套件 | 用途 |
|---|---|
| **syslog forwarder** (例如 nxlog, fluentd) | AuditLog → SIEM |
| **PAM webhook receiver** | 接 PAM 申請 ID → chain_id |
| **Defender for Endpoint** | 進階 EDR (需 Microsoft 365 E5 授權) |

---

## 九、安裝順序 (建議)

```
1. Windows Server 2022 + 加入網域
2. Windows Update 一次完整跑完
3. 跑 deploy\00_check_prereqs.ps1 確認環境
4. 安裝 Microsoft Visual C++ Redistributable
5. 安裝 SQL Server 2022 Express
6. 安裝 sqlcmd / SSMS (選)
7. 安裝 Python 3.11+
8. 安裝 NSSM
9. 跑 deploy\01_setup_directories.ps1
10. 跑 deploy\02_setup_ntfs_acl.ps1
11. 跑 deploy\03_install_openssh.ps1
12. 跑 deploy\04_create_sftp_accounts.ps1
13. 跑 deploy\05_setup_firewall.ps1
14. 跑 deploy\06_install_iis.ps1 (含安裝 IIS, 但 URL Rewrite/ARR 要手動下載)
15. 手動下載安裝 URL Rewrite + ARR
16. 跑 deploy\07_setup_gpo_policy.ps1
17. 跑 deploy\08_install_sqlexpress_notes.ps1 (建立 AuditLog DB)
18. 跑 deploy\09_setup_portal.ps1 (部署 Flask + NSSM)
19. 跑 deploy\10_setup_ntp.ps1
20. 跑 deploy\11_setup_firewall_log.ps1
21. 跑 deploy\12_install_ftps.ps1 (預設停用)
22. 跑 deploy\13_setup_defender.ps1
23. 跑 deploy\14_setup_quota_fsrm.ps1
24. 跑 deploy\15_setup_backup.ps1
25. 跑 deploy\16_setup_monitoring.ps1
26. 部署 SSL 憑證 (匯入 Cert:\LocalMachine\My)
27. 測試: Portal 登入 / SFTP 上傳 / SMB 下載 / 批次簽核
```

---

## 十、快速安裝確認指令 (一次列出狀態)

```powershell
# 角色功能
Get-WindowsFeature | Where-Object { $_.Name -in 'Web-Server','Web-Ftp-Server','FS-Resource-Manager','Windows-Server-Backup','RSAT-AD-PowerShell' } | Format-Table Name, InstallState

# OpenSSH
Get-WindowsCapability -Online -Name 'OpenSSH.Server*' | Format-Table Name, State

# SQL Express
Get-Service -Name 'MSSQL$SQLEXPRESS' | Format-Table Name, Status, StartType

# Python
python --version
pip --version

# .NET Framework
(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full').Release  # 528040+ = 4.8

# IIS 模組
Get-WebGlobalModule | Where-Object { $_.Name -like '*Rewrite*' -or $_.Name -like '*ARR*' }

# 服務狀態
Get-Service sshd, W3SVC, MSSQL$SQLEXPRESS, LanmanServer, FTPSVC, WinDefend, W32Time | Format-Table Name, Status, StartType
```

---

## 十一、磁碟空間預估

| 項目 | 大小 |
|---|---|
| Windows Server 2022 + Update | 30 GB |
| SQL Express + AuditLog 1 年資料 | 5~10 GB |
| Python + 套件 | 1 GB |
| IIS + Portal app | 500 MB |
| 各 log 1 年 | 5 GB |
| 業務資料 (D:\DataExchange) | 視業務量, 建議 500 GB 起 |
| 備份本地暫存 | 100 GB |
| **建議規格** | **C: 200 GB + D: 1 TB** |
