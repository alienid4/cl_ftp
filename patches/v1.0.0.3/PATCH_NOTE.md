# Patch v1.0.0.3 — install_offline.ps1 完全 idempotent + 容錯 + OpenSSH FoD 失敗指引

| 項目 | 內容 |
|---|---|
| **Patch 編號** | v1.0.0.3 |
| **發布日期** | 2026-05-19 |
| **適用版本** | v1.0.0 (含 v1.0.0.1 已套用者) |
| **嚴重程度** | 🔴 高 (擋住 install_offline.ps1 在 OpenSSH 步驟) |
| **跳號說明** | 規範通常連號 v1.0.0.2, 但使用者明確指定 v1.0.0.3 (對應 SF 主機實際遭遇的第 3 個阻礙) |
| **相關 issue** | #007 (路徑) / #010 (本次 OpenSSH 0x800f0907) |

---

## 1. 問題描述 (Symptom)

跑 `install_offline.ps1` 到 Step 7 Windows Features 後段, OpenSSH capability 安裝失敗導致整個 script abort:

```
============================================================
 Step 07: Windows Features (IIS / FTP / FSRM / Backup / RSAT)
============================================================
[skip] Web-Server 已安裝
[skip] Web-WebServer 已安裝
... (其他 IIS 都 skip)
[exec] Add-WindowsCapability OpenSSH.Server~~~~0.0.1.0

Add-WindowsCapability : 失敗, 錯誤碼 = 0x800f0907
... CategoryInfo: NotSpecified
... FullyQualifiedErrorId: Microsoft.Dism.Commands.AddWindowsCapabilityCommand

(整個 script 中止, 後面的 Python 套件 / deploy 腳本都沒跑)
```

---

## 2. 根本原因 (Root cause)

### 2.1 OpenSSH 失敗根因

`0x800f0907` (CBS_E_INVALID_REPAIR_SOURCE) = **Windows 找不到 Features on Demand (FoD) source**。

OpenSSH.Server 是 Windows FoD package, 內網主機要裝它需要:
- A. 公司 WSUS 有 FoD package
- B. 從 Windows installation media 帶 sxs source
- C. 連網到 Windows Update

三條路任一不通 → 安裝失敗。

### 2.2 Script 設計缺陷

舊版 `install_offline.ps1`:
- `$ErrorActionPreference = 'Stop'` (任何錯誤都 abort)
- VC++ / Python / NSSM / sqlcmd / URL Rewrite / ARR 都**沒檢查「已裝就 skip」**
- OpenSSH 失敗沒 try-catch, 整個 script die

→ 使用者重跑時, 已裝的會嘗試重裝 (有風險), 失敗的會繼續擋路。

---

## 3. 修正內容 (What changed)

### 3.1 完全 idempotent

每個 step 都先檢查「已裝就 skip」:

| Step | 已裝偵測方式 |
|---|---|
| VC++ Redist | `HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64` 的 `Installed=1` |
| SQL Express | `Get-Service 'MSSQL$SQLEXPRESS'` 存在 |
| sqlcmd | `Get-Command sqlcmd.exe` 存在 |
| URL Rewrite | `Get-WebGlobalModule -Name 'RewriteModule'` 存在 |
| ARR | `Get-WebGlobalModule -Name 'ApplicationRequestRouting*'` 存在 |
| Python 3.11 | 3 個典型路徑 (`%LOCALAPPDATA%\Programs\Python\Python311\python.exe` 等) |
| NSSM | `C:\Tools\nssm.exe` 存在 |
| Windows Features | `Get-WindowsFeature -Name X` 的 `InstallState -eq 'Installed'` (舊版已有) |
| OpenSSH | `Get-WindowsCapability` 的 `State -eq 'Installed'` (舊版已有) |

→ **重跑 install_offline.ps1 安全**, 已裝的全 skip。

### 3.2 容錯設計

- `$ErrorActionPreference` 改為 `'Continue'` (主腳本不因單錯誤 die)
- 每個 step 用 `try-catch` 包裹, 失敗 → record warn → 繼續
- `RecordStep` 函式紀錄每步結果到 `$script:results`
- 結尾顯示 summary table:
  ```
  ----------------------------------------------------
  Step                      Status  Detail
  ----------------------------------------------------
  Step 0 前置檢查             ok
  VC++ Redist                skip    已安裝 14.40.33810
  SQL Express                skip    已安裝, 狀態 Running
  sqlcmd                     ok      安裝完成
  URL Rewrite                skip    已安裝
  ARR                        skip    已安裝
  Python 3.11                skip    已安裝: C:\Users\...
  NSSM                       skip    已存在: C:\Tools\nssm.exe
  Windows Features           ok      新裝 0, skip 19, fail 0
  OpenSSH.Server             fail    0x800f0907 無 FoD source
  Python 套件                ok      安裝完成
  deploy scripts             ok      成功 17, 失敗 0
  Portal appsettings         ok      D:\_portal\app\appsettings.json
  ----------------------------------------------------
  ```

### 3.3 OpenSSH 失敗給明確 fallback

```
[FAIL] OpenSSH 安裝失敗: 0x800f0907

常見原因: 0x800f0907 = 內網無 Windows Update / FoD source
解法 (擇一):
  A. 公司 WSUS 包進 OpenSSH FoD package (找系管確認)
  B. 從 Windows installation media 帶 sxs source:
     Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 `
         -Source <ISO-mount>\sources\sxs
  C. GUI 安裝 (短期):
     設定 → 應用程式 → 選用功能 → 新增功能 → OpenSSH Server
  D. 主機暫時開放 WU 連線, 裝完再關

其他套件繼續裝, OpenSSH 之後補上
```

---

## 4. 影響檔案

| 檔案 | 動作 |
|---|---|
| `deploy/offline/install_offline.ps1` | **完整重寫** |
| `docs/dev-log/issues_log.md` | **新增** #010 |
| `docs/dev-log/dev_journal.md` | **追加** entry |
| `patches/README.md` | **更新** 版本歷史 |

---

## 5. 套用方式

### 方法 A: 用 apply.ps1 (推薦)

```powershell
cd <SF-PROJECT-ROOT>
.\patches\v1.0.0.3\apply.ps1
```

### 方法 B: 手動覆蓋

```powershell
Copy-Item patches\v1.0.0.3\files\deploy\offline\install_offline.ps1 `
    deploy\offline\install_offline.ps1 -Force
```

---

## 6. 驗證

套用後重跑 install_offline.ps1:

```powershell
cd <SF-PROJECT-ROOT>\deploy\offline
.\install_offline.ps1
```

**預期看到** (假設前面已部分裝過):
```
[skip] VC++ Redist        已安裝 14.40.33810
[skip] SQL Express        已安裝, 狀態 Running
[skip] sqlcmd             已安裝: ...
[skip] URL Rewrite        已安裝
[skip] ARR                已安裝
[skip] Python 3.11        已安裝: ...
[skip] NSSM               已存在: C:\Tools\nssm.exe
[ok]   Windows Features   新裝 0, skip 19, fail 0
[fail] OpenSSH.Server     0x800f0907 無 FoD source (見上方解法)
[ok]   Python 套件        安裝完成
[ok]   deploy scripts     成功 17, 失敗 0
[ok]   Portal appsettings D:\_portal\app\appsettings.json

⚠️ 有 1 個 step 失敗, 請依上方提示處理後重跑此 script (idempotent)
```

→ OpenSSH 即使失敗, 其他步驟都會完成, 不再卡住整個流程。

---

## 7. OpenSSH 失敗後怎麼補

跟使用者公司**系統管理員 / 資安**反映:

**訴求**: 「SF 主機要裝 OpenSSH Server (Windows FoD), 但內網無 WSUS / FoD source, 請協助:」

| 選項 | 對方做什麼 |
|---|---|
| A | WSUS 加入 OpenSSH FoD package |
| B | 借用 Windows installation media (或 ISO), 我用 `-Source` 參數裝 |
| C | 開短期 Windows Update 連線 (僅本次安裝用) |
| D | 直接用 Windows 設定 GUI 裝 (短期可用, 但無法 silent) |

確認 OpenSSH 起來後, 重跑 install_offline.ps1 → OpenSSH step 變 `[skip] 已安裝`, 整體 100% OK。

---

## 8. 相關連結

- GitHub commit: (待 commit 後填入)
- 已知問題: [docs/dev-log/issues_log.md](../../docs/dev-log/issues_log.md) #010
- 工作日誌: [docs/dev-log/dev_journal.md](../../docs/dev-log/dev_journal.md)
