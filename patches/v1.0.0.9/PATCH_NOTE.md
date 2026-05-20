# Patch v1.0.0.9 — 路徑統一 + 多腳本 bug 修正 (Round 4)

| 項目 | 內容 |
|---|---|
| **Patch 編號** | v1.0.0.9 |
| **發布日期** | 2026-05-20 |
| **狀態** | ✅ 必裝 (修 v1.0.0.8 後跑 deploy/00-17 暴露的 7 個 bug) |
| **相關 issue** | #017 ~ #023 |
| **前置 patch** | v1.0.0.8 |

---

## 改了什麼 (7 處)

### 修 #1: `deploy/01_setup_directories.ps1` — _portal 路徑統一

**問題**: SQL DB 建立失敗 `D:\_portal\db\FileExchangeAudit.mdf 目錄查閱失敗`。
舊版把 `_portal` 建在 `D:\DataExchange\_portal\`, 但 sql schema 寫的是 `D:\_portal\db\` (一半腳本 hardcoded 用 `D:\_portal\`)。

**修法**: 拆兩個 root, 對齊規畫文件:
- `D:\DataExchange\` — 業務檔 (各部門 inbound / pending / archive / etc.)
- `D:\_portal\` — 系統檔 (app / logs / db / scripts / backups / ftps_pasv)

```powershell
.\01_setup_directories.ps1 -DataRoot 'D:\DataExchange' -PortalRoot 'D:\_portal'
```

### 修 #2: `deploy/02_setup_ntfs_acl.ps1` — 同樣拆 root

跟 #1 對齊, 加 `-DataRoot` / `-PortalRoot` 參數, 向後相容舊的 `-Root`。

### 修 #3: `deploy/04_create_sftp_accounts.ps1` — Description < 48 字元

**問題**: `New-LocalUser -Description "Department: FIN, do NOT use for interactive logon"` (49 字元) 超過 Windows 限制 (48), sftp_fin / sftp_ops 沒建到。

**修法**: 縮短為 `"SFTP $d dept account (no interactive logon)"` (約 44 字元)。

### 修 #4: `deploy/06_install_iis.ps1` — PhysicalPath 路徑修正

預設值從 `D:\DataExchange\_portal\app` 改 `D:\_portal\app`。

### 修 #5: `deploy/09_setup_portal.ps1` — Python 偵測 + 路徑修正

**問題 A**: `Get-Command python.exe` 找不到 user-only 安裝的 Python (`%LOCALAPPDATA%\Programs\Python\Python311\`)。
**修法 A**: 加 `Find-Python` 函式, 多重 fallback:
1. PATH 內 python.exe
2. User-only: `%LOCALAPPDATA%\Programs\Python\Python311\`
3. 系統: `C:\Python311\` / `C:\Program Files\Python311\`

**問題 B**: PortalTarget 預設 `D:\DataExchange\_portal\app` 跟其他腳本不一致。
**修法 B**: 改 `D:\_portal\app`。

### 修 #6: `deploy/11_setup_firewall_log.ps1` — Set-NetFirewallProfile 參數錯誤

**問題**: `Set-NetFirewallProfile -LogAllowed True` 在 Server 2022 PS 5.1 環境炸 `Windows System Error 87` (ERROR_INVALID_PARAMETER)。

**修法**:
1. 用 `[Microsoft.PowerShell.Cmdletization.GeneratedTypes.NetFirewall.GpoBoolean]::True` enum 物件 (取代字串 `True`)
2. Fallback 到 `netsh advfirewall set <profile> logging`, 確保任何版本都能設

### 修 #7: `deploy/12_install_ftps.ps1` — FTP 授權 idempotent

**問題**: `Add-WebConfiguration -Filter "/system.ftpServer/security/authorization"` 重跑時加重複, 炸「無法新增類型 'add' 的重複集合項目」。

**修法**: 加 `Get-WebConfiguration` 先檢查是否已加, 已加則 skip; 沒加才 Add, 並包 try-catch。

---

## 套用方式

```
雙擊 run_patch.cmd
```

或 PowerShell:
```powershell
.\install_patch.ps1
```

腳本拷 7 個 deploy/ 檔覆蓋。

---

## 套完之後

### 重跑流程驗證

```powershell
cd <sf_offline_bundle>\deploy

# 1. 重新建立完整目錄 (現在會建 D:\_portal\ 跟 D:\DataExchange\)
.\01_setup_directories.ps1

# 2. 設定 NTFS ACL (D:\_portal\ 跟 D:\DataExchange\ 都設)
.\02_setup_ntfs_acl.ps1

# 3. 建剩下的 SFTP 帳號 (sftp_fin / sftp_ops)
.\04_create_sftp_accounts.ps1
# (sftp_hr 已存在會 skip, 只新建 fin + ops)

# 4. 重跑 SQL DB 建立 (現在 D:\_portal\db\ 存在了)
cd ..\
& "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\SQLCMD.EXE" -S .\SQLEXPRESS -E -i sql\01_create_db.sql

# 5. 跑 Portal (現在能找到 Python)
cd deploy
.\09_setup_portal.ps1

# 6. 補跑防火牆 log (現在用 enum + netsh fallback)
.\11_setup_firewall_log.ps1

# 7. 補跑 FTPS (現在 idempotent)
.\12_install_ftps.ps1
```

或一次重跑 install_offline:
```powershell
cd <sf_offline_bundle>\deploy\offline
.\install_offline.ps1
```

預期 summary table 大部分綠 / skip, 剩下:
- URL Rewrite + ARR exit=-2144337918 (可能已裝, 看 IIS 確認)
- 06 IIS HTTPS 綁定 fail (需 -CertThumbprint, 之後申請 SSL)
- 13 WinDefend Stopped (公司可能用其他 EDR, 不阻塞)

---

## 影響檔案

| 檔案 | 動作 |
|---|---|
| `deploy/01_setup_directories.ps1` | 修改 (拆 DataRoot + PortalRoot, 加 samba 目錄) |
| `deploy/02_setup_ntfs_acl.ps1` | 修改 (同樣拆 root) |
| `deploy/04_create_sftp_accounts.ps1` | 修改 (Description 縮短) |
| `deploy/06_install_iis.ps1` | 修改 (PhysicalPath 路徑) |
| `deploy/09_setup_portal.ps1` | 修改 (Python 偵測 + 路徑) |
| `deploy/11_setup_firewall_log.ps1` | 修改 (Set-NetFirewallProfile + netsh fallback) |
| `deploy/12_install_ftps.ps1` | 修改 (idempotent Add-WebConfiguration) |

7 個檔。

---

## 還沒解的 (給後續處理)

| 項目 | 處理方式 |
|---|---|
| URL Rewrite / ARR exit=-2144337918 | 用 `Get-WebGlobalModule \| where Name -match 'rewrite\|ARR'` 確認, 如已裝就 OK skip |
| IIS HTTPS 綁定需 -CertThumbprint | 申請公司 SSL 憑證, 匯入 Cert:\LocalMachine\My, 重跑 06 帶 thumbprint |
| WinDefend service Stopped | 公司可能用 CrowdStrike/Defender ATP 等其他 EDR, 確認後跳過此項 |
| 03_install_openssh.ps1 sshd 還是 warn | 套 v1.0.0.8 後重跑 03 即可解 (v1.0.0.8 修 sshd_config Subsystem + Banner) |

---

## 相關連結

- 對應 issues: #017 ~ #023 (詳見 docs/dev-log/issues_log.md)
- 前置 patch: [v1.0.0.8](../v1.0.0.8/) (sshd_config + banner)
- 前置 patch: [v1.0.0.7](../v1.0.0.7/) (PS 5.1 相容 + portable 雙軌)
- 規畫文件: D:\_portal 對齊主管圖 + sql schema
