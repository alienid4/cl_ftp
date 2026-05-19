# Patch v1.0.0.7 — Round 2 修正 (PS 5.1 相容 + portable OpenSSH 雙軌 + 門檻調整)

| 項目 | 內容 |
|---|---|
| **Patch 編號** | v1.0.0.7 |
| **發布日期** | 2026-05-19 ~ 20 |
| **狀態** | ✅ 必裝 (修 v1.0.0.5/6 部署後新發現的 5 個 bug) |
| **相關 issue** | #012, #013, #014, #015 |
| **前置 patch** | v1.0.0.5 (OpenSSH portable), v1.0.0.6 (patch installer) |

---

## 改了什麼 (5 處)

### 修 #1: `deploy/00_check_prereqs.ps1` — D: 磁碟門檻 100 → 30 GB

97.4 GB 被判 FAIL 擋住後續步驟。
門檻降到 30 GB (足夠啟動), <100 GB 仍 OK 但提示「生產建議 >= 100 GB」。

### 修 #2: `deploy/01_setup_directories.ps1` — PS 5.1 解析錯誤

PS 5.1 不接受 method-call argument 內直接放 cmdlet (PS 7 可以), 必須用雙括號:

```powershell
# 舊 (PS 7 OK, PS 5.1 parser error)
$paths.Add(Join-Path $Root $d)

# 新 (兩種 PS 都通)
$paths.Add( (Join-Path $Root $d) )
```

並改用 `[List[string]]::new()` 替代 `New-Object`。

### 修 #3: `deploy/03_install_openssh.ps1` — portable OpenSSH 雙軌偵測

portable (Win32-OpenSSH zip) 裝完不會註冊到 WindowsCapability, 03 重跑時想再裝一次。
新邏輯:

1. 先看 `Get-Service sshd` 存在 → portable / FoD 通用, skip 安裝
2. 否則才嘗試 `Add-WindowsCapability` (FoD 路線)
3. FoD 失敗時提示走 portable 路線 + exit 1 (不 abort 整個流程)

### 修 #4: `deploy/offline/install_offline.ps1` Step 7 — 同樣 portable 雙軌偵測

跟 #3 同邏輯, 重跑時 OpenSSH 那行從 fail 變 skip。
fail message 加 "A. ⭐ Portable 路線 (推薦)" 排第一。

### 修 #5: `scripts/health_check.ps1` — 兩處 null / type bug

**Bug A** (line 102): `Select-String` 找不到時回 null, `.ToString()` 炸:

```powershell
# 新: null-safe
$ntpMatch = $ntpStatus | Select-String -Pattern 'Source:.*$' | Select-Object -First 1
$ntpSrc = if ($ntpMatch) { $ntpMatch.ToString().Trim() } else { '(無 Source 資訊)' }
```

**Bug B** (line 152): `$defStatus.AntivirusSignatureLastUpdated` 在某些 PS 5.1 環境是 string, op_Subtraction 算不出來:

```powershell
# 新: 強制 cast + try-catch
$sigDate = [datetime]$defStatus.AntivirusSignatureLastUpdated
$sigAge = ((Get-Date) - $sigDate).TotalHours
```

---

## 怎麼套用

```powershell
# 雙擊
run_patch.cmd

# 或 PowerShell
.\install_patch.ps1
```

腳本自動偵測 SF bundle 位置, 拷 5 個檔覆蓋。

---

## 影響檔案

| 檔案 | 動作 |
|---|---|
| `deploy/00_check_prereqs.ps1` | 修改 (門檻) |
| `deploy/01_setup_directories.ps1` | 修改 (PS 5.1 語法) |
| `deploy/03_install_openssh.ps1` | 修改 (portable 偵測) |
| `deploy/offline/install_offline.ps1` | 修改 (Step 7 portable 偵測) |
| `scripts/health_check.ps1` | 修改 (兩處 null/type) |

5 個檔, 13 KB patch zip。

---

## 套用後重跑驗證

```powershell
# 1. 重跑 install_offline.ps1 — 應該 summary 全 ok / skip, 不再有紅字
cd <sf_offline_bundle>\deploy\offline
.\install_offline.ps1

# 2. 跑 deploy/00 + 01 + 03 確認 PS 5.1 不再炸
cd <sf_offline_bundle>\deploy
.\00_check_prereqs.ps1     # D: 97.4 GB 應變 OK (有提示)
.\01_setup_directories.ps1  # PS 5.1 不再 parser error
.\03_install_openssh.ps1    # 看到 [skip] OpenSSH 已安裝

# 3. 跑 health_check 全 OK (除 WinDefend / DB 連線 / DailyBackup 等業務問題)
cd <sf_offline_bundle>\scripts
.\health_check.ps1
```

---

## 還沒解的 (給之後 patch / startup_sop 處理)

| 項目 | 處理時機 |
|---|---|
| WinDefend service Stopped | startup_sop / 13_setup_defender.ps1 |
| AuditLog DB 連線 fail | startup_sop Step 5 建 DB schema |
| SF_DailyBackup task 從沒跑過 | startup_sop Step 後設定排程 |
| Event Log Application 21 筆 Error | 看具體錯誤再判斷 |

這些是「業務狀態」, 不是「腳本 bug」, 留給 startup_sop 8 步流程處理。
