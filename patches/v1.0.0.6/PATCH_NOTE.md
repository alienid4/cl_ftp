# Patch v1.0.0.6 — Patch 安裝器通用化 + OpenSSH zip auto-find + fetch helper

| 項目 | 內容 |
|---|---|
| **Patch 編號** | v1.0.0.6 |
| **發布日期** | 2026-05-19 |
| **狀態** | ✅ UX 改進 |
| **相關 issue** | #011 (使用者反饋: patch 想任意目錄跑 + zip 想自動找) |
| **前置 patch** | v1.0.0.5 (OpenSSH Portable 基礎 installer) |

---

## 改了什麼

### 改進 1: `install_patch.ps1` 取代舊 `apply.ps1` — 任意目錄都能跑

舊 `apply.ps1` 必須在 `<SF-PROJECT-ROOT>/patches/v1.0.0.X/` 結構下才能跑 (自動偵測父兩層)。
新 `install_patch.ps1` 三種模式擇一:

```powershell
# 模式 1: 預設 — auto 偵測 SF root (跟 apply.ps1 一樣行為)
.\install_patch.ps1

# 模式 2: -Here — 拷到當前目錄 (適合單獨下載 patch zip 解壓)
.\install_patch.ps1 -Here

# 模式 3: -Target — 指定路徑
.\install_patch.ps1 -Target 'C:\Users\me\Desktop\sf_bundle\'
```

### 改進 2: `install_openssh_portable.ps1` — `-ZipPath` 變可選, 自動找 zip

舊版必須帶 `-ZipPath 'D:\OpenSSH-Win64.zip'`。新版不帶參數也能跑, 會自動掃以下位置:

1. 當前目錄 `(Get-Location)`
2. 腳本所在目錄 `$PSScriptRoot`
3. `C:\ClaudeHome\`
4. `D:\install\`
5. `D:\`
6. `C:\Temp\`
7. `$HOME\Downloads`

找到 `OpenSSH-Win64*.zip` 就用 (萬一檔名有版號也通配)。

```powershell
# 舊用法 (還能用)
.\scripts\install_openssh_portable.ps1 -ZipPath 'D:\install\OpenSSH-Win64.zip'

# 新用法 (zip 放在常用位置就不用帶參數)
.\scripts\install_openssh_portable.ps1
```

### 改進 3: 新增 `fetch_openssh_portable.ps1` — 外網 PC 一鍵抓 + 算 SHA256

```powershell
# 在外網 PC 跑 (不是 SF 主機!)
.\scripts\fetch_openssh_portable.ps1 -OutDir 'D:\sf_install\'
```

腳本會:
1. 連 PowerShell Team GitHub API 查最新 release
2. 下載 `OpenSSH-Win64.zip` 到指定目錄
3. 算 SHA256 寫到 `.sha256.txt` 旁邊檔
4. 提示「拷 USB → SF 主機驗 hash → 跑 install_openssh_portable.ps1」

---

## 為什麼不直接把 OpenSSH-Win64.zip 上傳到我們 GitHub Release

| 考量 | 說明 |
|---|---|
| **License & 維護** | Win32-OpenSSH 是 PowerShell Team (Microsoft) MIT 授權, 雖可 redistribute, 但要跟 upstream 版本, 維護負擔大 |
| **安全鏈** | 使用者直接從 PowerShell Team 官方抓, 簽名鏈完整, 不經第三方 (我們) |
| **版本即時** | Upstream 新版出來, 使用者直接抓最新, 不用等我們同步 |
| **資料責任** | 我們的 repo 範圍是 SF 主機部署腳本, 不是 mirror 別人的 binary |

→ 寫個 fetcher 比 mirror zip 乾淨。

---

## 使用情境

### 情境 A: 從 SF-PROJECT-ROOT 套 patch (內網)

```powershell
# 1. 把 patches/v1.0.0.6 拷進 SF root
# 2. 在 SF root 跑:
cd C:\Users\me\Desktop\sf_offline_bundle_20260519_0901\
.\patches\v1.0.0.6\install_patch.ps1
```

### 情境 B: 單獨下載 patch zip, 任意目錄解壓 (新)

```powershell
# 1. 下載 patch zip
# 2. 解壓到 C:\Temp\patch_v1.0.0.6\
# 3. 在解壓目錄跑:
cd C:\Temp\patch_v1.0.0.6\
.\install_patch.ps1 -Here

# 結果: C:\Temp\patch_v1.0.0.6\scripts\install_openssh_portable.ps1 + fetch_openssh_portable.ps1
```

### 情境 C: 指定 SF root (例如不在當前目錄)

```powershell
.\install_patch.ps1 -Target 'D:\sf_deployments\bundle_20260519\'
```

---

## 完整流程 (外網 → 內網)

```
[外網 PC (有 Internet)]                            [SF 主機 (內網)]
                                                    
1. clone or download cl_ftp repo                    
2. cd cl_ftp\                                       
3. .\scripts\fetch_openssh_portable.ps1     ──USB──► 4. .\patches\v1.0.0.6\install_patch.ps1
   → 抓 OpenSSH-Win64.zip + sha256                     → 拷 scripts/ 進 SF root
                                                    5. Get-FileHash 對比 SHA256 (驗證沒被改)
                                                    6. .\scripts\install_openssh_portable.ps1
                                                       → auto-find zip → 解壓裝 → service 啟動
                                                    
                                            完成
```

---

## 影響檔案

| 檔案 | 動作 |
|---|---|
| `scripts/install_openssh_portable.ps1` | **修改** (auto-find zip) |
| `scripts/fetch_openssh_portable.ps1` | **新增** |
| `patches/v1.0.0.6/install_patch.ps1` | **新增** (取代 apply.ps1 概念) |
| `patches/v1.0.0.6/files/scripts/` | (鏡像上面 2 個) |
| `patches/v1.0.0.6/PATCH_NOTE.md` | 本檔 |
| `patches/v1.0.0.6/README.md` | 給單獨下載 patch zip 的使用者看 |

---

## 套用方式 (三選一)

### 方法 A: 從 SF-PROJECT-ROOT 套

```powershell
cd <SF-PROJECT-ROOT>
.\patches\v1.0.0.6\install_patch.ps1
```

### 方法 B: 單獨下載 patch zip, 任意目錄

```powershell
# 解壓 patch zip 後在解壓目錄:
.\install_patch.ps1 -Here
```

### 方法 C: 手動拷貝

```powershell
Copy-Item patches\v1.0.0.6\files\scripts\*.ps1 scripts\ -Force
```

---

## 驗證

```powershell
# 1. 兩個腳本就位
Get-Item .\scripts\install_openssh_portable.ps1
Get-Item .\scripts\fetch_openssh_portable.ps1

# 2. install_openssh_portable.ps1 不帶參數 dry-run, 應該自動找 zip
.\scripts\install_openssh_portable.ps1 -DryRun

# 3. 外網 PC 跑 fetch (確認能連 PowerShell Team)
.\scripts\fetch_openssh_portable.ps1 -OutDir .

# 4. 帶回 SF 主機, 不帶參數跑 install
.\scripts\install_openssh_portable.ps1
```

---

## 相關連結

- 對應 issue: [issues_log #010](../../docs/dev-log/issues_log.md) (OpenSSH 0x800f0907)
- 對應 issue: #011 (UX: patch 任意目錄 + zip 自動找) — 本 patch
- 前一個 patch: [v1.0.0.5](../v1.0.0.5/) (OpenSSH Portable 基礎 installer)
- Win32-OpenSSH 官方: https://github.com/PowerShell/Win32-OpenSSH/releases
