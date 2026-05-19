# 已知問題 / Known Issues

部署過程中遇到的問題與解法。

---

## #1 install_offline.ps1 報「找不到 installers 目錄」 (v1.0.0)

### 症狀

在 SF 主機跑 `install_offline.ps1` 後, Step 0 前置檢查失敗:

```
============================================================
 Step 00: 前置檢查
============================================================
[FAIL] 找不到 installers 目錄: ...\deploy\offline\installers
  確認 bundle 完整解壓
```

### 原因

`fetch_binaries_win11.ps1` 把套件下載到 `sf_binaries/installers/` 與 `sf_binaries/python_wheels/`, 但 `install_offline.ps1` 預期它們直接在 `BundleDir` 下 (`BundleDir/installers/` 與 `BundleDir/python_wheels/`)。

兩個腳本路徑約定不一致, 造成路徑找不到。

### 解法 A — 用最新版 install_offline.ps1 (v1.0.1+)

最新 commit `63b725c` 起, `install_offline.ps1` 會**自動偵測** `sf_binaries/` 子目錄結構, 無需手動處理。

從 GitHub 拉最新版:
```powershell
git pull origin main
```

### 解法 B — 手動 Move (一次性, 適合內網)

在 SF 主機跑這 3 行:
```powershell
cd C:\Users\<USER>\Desktop\sf_offline_bundle_<TS>\deploy\offline

Move-Item .\sf_binaries\installers .\installers
Move-Item .\sf_binaries\python_wheels .\python_wheels

.\install_offline.ps1
```

### 解法 C — 用 patch 腳本 (推薦, 不會搞錯)

```powershell
.\scripts\patch_bundle_paths.ps1
```

腳本會自動偵測 `sf_binaries/` 並把 installers / python_wheels 移到正確位置。詳見 `scripts\patch_bundle_paths.ps1`。

---

## #2 PowerShell 5.1 讀 .ps1 中文亂碼 / 解析錯誤

### 症狀

```
運算式或陳述式中有未預期的 '}' 語彙基元
字串遺漏結尾字元: "。
```

### 原因

Windows PowerShell 5.1 預設用 ANSI (Big5) 讀 .ps1 檔。若 .ps1 是 UTF-8 (無 BOM) 且含中文, PowerShell 會解讀成亂碼, 進而 parse error。

### 解法

所有 .ps1 必須是 **UTF-8 with BOM**。本專案的 .ps1 都已加 BOM。若您自己新增 / 修改 .ps1, 確保用 BOM 存:

```powershell
# 把任一檔案重存為 UTF-8 BOM
$path = 'your-script.ps1'
$c = [System.IO.File]::ReadAllText($path)
[System.IO.File]::WriteAllText($path, $c, [System.Text.UTF8Encoding]::new($true))
```

或使用 VSCode 右下角 encoding 切換為「UTF-8 with BOM」。

---

## #3 NSSM 下載失敗 (503)

### 症狀

`fetch_binaries_win11.ps1` 跑到 NSSM 時:
```
[FAIL] 遠端伺服器傳回一個錯誤: (503) 伺服器無法使用。
```

### 原因

`nssm.cc` 偶有伺服器問題, 或 IP 暫時被擋。

### 解法

備援來源:
1. https://sourceforge.net/projects/nssm/files/2.24/nssm-2.24.zip/download
2. `winget install NSSM.NSSM` (在能上網的 Win11)
3. 從別人下載過的 NSSM zip 拷一份

下載後存到:
```
sf_binaries\installers\nssm-2.24.zip
```

---

## #4 Python 是 Windows Store stub

### 症狀

```powershell
python --version
```
跳出 Microsoft Store 安裝頁面, 或返回 exit code 49。

### 原因

Windows 11 內建 `python.exe` 在 `C:\Users\<USER>\AppData\Local\Microsoft\WindowsApps\` 是 Microsoft Store 的 stub, 不是真的 Python。

### 解法

用 bundle 內的 python installer 安裝:
```powershell
& sf_binaries\installers\python-3.11.9-amd64.exe /quiet InstallAllUsers=0 PrependPath=0 Include_test=0
```

裝在使用者目錄 (`%LOCALAPPDATA%\Programs\Python\Python311\`), 不改 PATH。

使用時用絕對路徑:
```powershell
$python = "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe"
& $python --version
```

---

## #5 requirements.txt 編碼錯誤 (pip download)

### 症狀

```
UnicodeDecodeError: 'cp950' codec can't decode byte 0x97
```

### 原因

`requirements.txt` 是 UTF-8 (無 BOM), pip 在中文 Windows 系統用 cp950 (Big5) 讀。

### 解法

把 requirements.txt 重存為 UTF-8 with BOM:
```powershell
$path = 'portal\requirements.txt'
$c = [System.IO.File]::ReadAllText($path)
[System.IO.File]::WriteAllText($path, $c, [System.Text.UTF8Encoding]::new($true))
```

---

## #6 OneDrive 占用 Desktop, Compress-Archive 失敗

### 症狀

```
Compress-Archive : The path 'C:\Users\<USER>\Desktop' either does not exist or is not a valid file system path.
```

### 原因

OneDrive for Business 接管了 `C:\Users\<USER>\Desktop`, 把它 redirect 到 `C:\Users\<USER>\OneDrive\桌面\`。`Compress-Archive` 在某些情況不認 OneDrive 路徑。

### 解法

打包輸出改放別處, 例如:
```powershell
$dest = 'C:\ClaudeHome\bundle_output\sf_offline_bundle.zip'
```

或先停用 OneDrive Desktop 同步, 但這影響範圍大, 不推薦。

---

## #7 SQL Express 是 CHT 版, install_offline.ps1 找不到

### 症狀

install_offline.ps1 預設找 `SQLEXPR_x64_ENU.exe` (英文版), 但您下載的可能是 `SQLEXPR_x64_CHT.exe` (繁體中文版)。

### 解法

最新 commit 起, `install_offline.ps1` 已支援所有語系: ENU / CHT / CHS / JPN / KOR / DEU / FRA。

舊版可以手動改 `install_offline.ps1` 那個 `$sqlExpr` 變數的對應語系字串。

---

## #8 GitHub 上傳大檔受限

### 症狀

把 343 MB zip push 上 GitHub 被拒, 或 GitHub Release 上傳大檔卡住 / 失敗。

### 原因 / 限制

| 機制 | 上限 |
|---|---|
| `git push` (進 repo) | 單檔 100 MB, repo 建議 < 1 GB |
| Git LFS | 1 GB 免費, 多收費 |
| GitHub Release attach | **2 GB / 檔** (但 Public Release 公開 binary 有資安考量) |

### 解法

binary 不進 git, 走以下管道:
- 公司內部檔案 share / SharePoint / OneDrive
- USB 實體媒體
- 公司 Artifactory / Nexus
- 自架 server (HTTP/SFTP)

詳見 `docs/software_distribution.md`。

---

## 回報新問題

遇到本文件沒列的問題, 請開 [GitHub Issue](https://github.com/alienid4/cl_ftp/issues) 或私訊維護者 (見 `SECURITY.md`)。
