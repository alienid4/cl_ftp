# SF 軟體分發策略

> **問題**: 600 MB bundle 太大, 不能放 GitHub。
> **解法**: 程式碼進 git, binary 走另一條通道。

---

## 一、檔案分類

### A. 進 GitHub (~5 MB, 可公開或私有)
- 程式碼 (PowerShell / Python)
- 設定範本 (sshd_config, web.config, .env.example)
- SQL Schema
- 文件 (md, html mockup)
- mockup 用的 CSS (cathay.css 也算)

### B. 不進 GitHub (~600 MB, 走分發通道)
- Microsoft 安裝檔 (SQL Express, URL Rewrite, ARR, VC++ Redist, Python, sqlcmd)
- Python wheels (`.whl` 檔)
- SSL 憑證 (`.pfx`, `.pem`) — **絕對不能進 git, 任何地方都不行**
- 實際的 appsettings.json (含密碼)

→ `.gitignore` 已涵蓋, 不會誤推。

---

## 二、binary 分發 5 種方式 (依公司資源選)

### 方式 1: 公司內部檔案 Share (最常見)

```
\\fileserver\IT\SF\offline_bundle\
├── sf_offline_bundle_20260518.zip      (600 MB)
└── sf_offline_bundle_20260601.zip      (定期更新版)
```

**優點**: 已有, 不用申請。
**缺點**: 需要 SMB 連線權限。

### 方式 2: OneDrive for Business / SharePoint

如果公司用 Microsoft 365:
- 上傳到 IT 部門的 OneDrive 共享資料夾
- 或建立 SharePoint 文件庫

**優點**: 帶寬好, 跨地端可用, 公司認證即可。
**缺點**: 公司不一定允許 IT 工具放 OneDrive。

### 方式 3: 公司 Artifactory / Nexus (DevOps 標配)

如果有套件管理平台:
```
artifactory.corp.local/sf/installers/
├── SQLEXPR_x64_ENU.exe
├── python-3.11.9-amd64.exe
└── ...

artifactory.corp.local/sf/python-wheels/
├── flask-3.0.0.whl
└── ...
```

`build_offline_bundle.ps1` 改成從 Artifactory 抓:

```powershell
# 原本:
Invoke-WebRequest -Uri 'https://www.python.org/.../python-3.11.9-amd64.exe' -OutFile ...

# 改成:
Invoke-WebRequest -Uri 'https://artifactory.corp.local/sf/installers/python-3.11.9-amd64.exe' -OutFile ...
```

`pip install --index-url https://artifactory.corp.local/api/pypi/sf-pypi/simple/` 也直接走公司 PyPI mirror。

**優點**: 內網可直接抓, 不用打包 zip。
**缺點**: 要先請 DevOps 申請空間。

### 方式 4: SCCM Package (大企業)

把 600 MB bundle 包成 SCCM Application, 由 SCCM 推到 SF 主機。

**優點**: IT 標準流程, 集中管理。
**缺點**: 申請流程久, 不適合快速迭代。

### 方式 5: USB 實體媒體 (傳統但可靠)

打包一次, 拷貝到 USB, IT 帶進機房。

**優點**: 零依賴, 最安全 (氣隙網路也可用)。
**缺點**: 不適合頻繁更新。

---

## 三、推薦組合 (依公司成熟度)

| 公司類型 | 程式碼放 | binary 放 |
|---|---|---|
| 中小企業 / 沒 DevOps 平台 | GitHub Private | 公司 share + USB 備援 |
| 中大型 / 有 SharePoint | GitHub Private | SharePoint 文件庫 |
| DevOps 成熟 / 金融業 | GitLab Self-hosted | Artifactory / Nexus |
| 高度管制 (氣隙) | 內部 GitLab | USB 一次性 |

→ 金融業常見組合: **GitLab Self-hosted + Artifactory** (我猜您公司是這種, 但要確認)。

---

## 四、實際操作 SOP

### Step 1: 把專案推到 git (只有 code)

```powershell
cd C:\ClaudeHome\SFTP
git init
git add .                           # .gitignore 已過濾 binary
git commit -m "Initial commit"
git remote add origin <您公司 git URL>
git push -u origin main
```

預期推上去的大小: **< 5 MB**。

### Step 2: 一次性打包 binary

```powershell
cd deploy\offline
.\build_offline_bundle.ps1
# 產生 bundle_output\sf_offline_bundle_20260518.zip (~600 MB)
```

### Step 3: 把 binary 放分發通道

```powershell
# 方式 1: SMB share
Copy-Item .\bundle_output\sf_offline_bundle_*.zip \\fileserver\IT\SF\

# 方式 2: Artifactory
& jfrog rt u sf_offline_bundle_*.zip sf-bundles/

# 方式 3: USB
Copy-Item .\bundle_output\sf_offline_bundle_*.zip E:\
```

### Step 4: SF 主機部署時

```powershell
# 從 git clone 程式碼
git clone <repo-url> C:\ClaudeHome\SFTP
cd C:\ClaudeHome\SFTP

# 從 share / Artifactory / USB 取 bundle
Copy-Item \\fileserver\IT\SF\sf_offline_bundle_20260518.zip C:\Temp\
Expand-Archive C:\Temp\sf_offline_bundle_20260518.zip -DestinationPath . -Force

# 跑安裝
.\deploy\offline\install_offline.ps1
```

---

## 五、變化型: build script 拆兩個

```powershell
# 在 git 上的 deploy/offline/
.\fetch_packages.ps1     # 從公司 Artifactory / share 拉 binary (內網)
.\build_offline_bundle.ps1  # 從外網下載 binary (僅外網能用)
.\install_offline.ps1    # 在 SF 主機跑
```

→ 內外網都有對應的「取套件」腳本, 統一給 install_offline.ps1 用。

我可以額外加 `fetch_packages_internal.ps1` (從公司 share / Artifactory 抓), 讓內網工作站也能組 bundle。要做嗎?

---

## 六、敏感檔特別提醒

| 檔案 | 絕對不能進 git |
|---|---|
| `*.pfx` / `*.key` / `*.pem` | SSL 私鑰 |
| `appsettings.json` (實際版本, 含 DB 密碼) | DB connection string |
| `.env` | 環境變數含 AD bind 密碼 |
| `nssm-2.24/*.exe` (其實可進但大) | 也可以放 share |

`.gitignore` 已涵蓋以上。**如果不小心 commit 了 SSL 私鑰, 必須立即作廢憑證 + git history 清除 + 通報資安**。

---

## 七、Quick Reference

```
GitHub Repo:           ~5 MB   (程式碼 + 文件 + 範本)
公司 share / Art:      ~600 MB (Microsoft / 開源 binary)
DBA 那邊:              SQL DB instance (第二階段)
PAM 那邊:              u01~u0N 密碼納管
AD 那邊:               g_u0X_approvers + dept_*_view 群組
SSL 憑證:              公司 PKI 核發
```

完整 SF 部署 = git pull + 從 share 取 bundle + 跑 install_offline.ps1。
