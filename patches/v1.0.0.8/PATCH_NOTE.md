# Patch v1.0.0.8 — sshd_config 啟動修正 + 自動建 banner.txt

| 項目 | 內容 |
|---|---|
| **Patch 編號** | v1.0.0.8 |
| **發布日期** | 2026-05-20 |
| **狀態** | ✅ 必裝 (修 sshd restart 失敗) |
| **相關 issue** | #016 |
| **前置 patch** | v1.0.0.7 |

---

## 解了什麼

套完 v1.0.0.7 + portable OpenSSH 之後, 跑 03_install_openssh.ps1 出現:

```
[warn] 03_install_openssh.ps1 異常: 無法啟動服務 'OpenSSH SSH Server (sshd)'
```

兩個原因:

### 原因 1: sshd_config `Subsystem sftp sftp-server.exe` 路徑找不到

- Portable Win32-OpenSSH 的 `sftp-server.exe` 在 `C:\Program Files\OpenSSH\`
- FoD 版在 `C:\Windows\System32\OpenSSH\`
- 寫死 `sftp-server.exe` 在 portable 環境找不到 (不在 PATH)

**修法**: 改用 `internal-sftp` (sshd 內建, 不依賴外部 binary)。Portable / FoD 都通。

```
Subsystem sftp internal-sftp
```

### 原因 2: `Banner C:/ProgramData/ssh/banner.txt` 檔案不存在

sshd 啟動時讀不到 banner 直接 fail。

**修法**: `03_install_openssh.ps1` 套 sshd_config 前**自動建立 banner.txt** 預設內容 (對齊金融業內外稽)。

---

## 改了什麼

### 修 #1: `config/sshd_config`

```diff
-# 注意: Windows 版用內建 sftp-server.exe
-Subsystem sftp sftp-server.exe
+# 用 internal-sftp (sshd 內建, 不依賴外部 binary)
+# 這樣 portable (C:\Program Files\OpenSSH\) 跟 FoD (C:\Windows\System32\OpenSSH\)
+# 兩種安裝方式都能跑
+Subsystem sftp internal-sftp
```

### 修 #2: `deploy/03_install_openssh.ps1`

- 套 sshd_config 前**自動建立 banner.txt** (若不存在)
- 預設內容: 「Authorized access only. All activities are logged...」
- 設 NTFS ACL: Admin/SYSTEM 完整, Users 唯讀
- Restart-Service 加 try-catch + 友善診斷 (Event Log + sshd -t 語法檢查 + 還原備份)

---

## 套用方式

```
雙擊 run_patch.cmd
```

或:
```powershell
.\install_patch.ps1
```

腳本拷 2 個檔覆蓋:
- `config/sshd_config`
- `deploy/03_install_openssh.ps1`

---

## 套完之後

### 自動方式 (推薦)

重跑 03 自動修 sshd_config + 建 banner.txt + restart:

```powershell
cd <sf_offline_bundle>\deploy
.\03_install_openssh.ps1
```

### 手動方式 (5 秒一行)

如果不想重跑 03, 直接改 SF 主機現有的 sshd_config:

```powershell
# 改 Subsystem + 註解 Banner + 建 banner.txt
$c = Get-Content 'C:\ProgramData\ssh\sshd_config' -Raw
$c = $c -replace 'Subsystem sftp sftp-server\.exe', 'Subsystem sftp internal-sftp'
Set-Content 'C:\ProgramData\ssh\sshd_config' -Value $c -Encoding ASCII

# 建 banner.txt
@'
=============================================================
  SF File Exchange Server (SFTP)
  Authorized access only. All activities are logged.
=============================================================
'@ | Set-Content 'C:\ProgramData\ssh\banner.txt' -Encoding ASCII

Restart-Service sshd
Get-Service sshd
```

預期: `sshd Running`。

---

## 驗證

```powershell
# 1. sshd 跑起來
Get-Service sshd | Format-Table Name, Status, StartType

# 2. 語法檢查 (應該 0 error)
& 'C:\Program Files\OpenSSH\sshd.exe' -t -f 'C:\ProgramData\ssh\sshd_config'

# 3. Port 22
Test-NetConnection localhost -Port 22

# 4. 從別台主機 sftp 測 (若有)
sftp sftp_hr@<SF-IP>
```

---

## 影響檔案

| 檔案 | 動作 |
|---|---|
| `config/sshd_config` | 修改 (Subsystem internal-sftp) |
| `deploy/03_install_openssh.ps1` | 修改 (banner.txt + try-catch) |

---

## 相關連結

- 對應 issue: [issues_log #016](../../docs/dev-log/issues_log.md)
- 前置 patch: [v1.0.0.7](../v1.0.0.7/)
- 起點 patch: [v1.0.0.5](../v1.0.0.5/) (OpenSSH portable)
