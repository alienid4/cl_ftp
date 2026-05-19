# SF USB 分發 SOP

> 公司內網無法下載軟體, 走 USB 帶 ~600 MB bundle 進去。

---

## 一、整體流程

```
[1] 申請 USB           IT 申請流程 (1-2 天)
        │
        ▼
[2] 外網工作站打包      .\build_offline_bundle.ps1
        │
        │ 產出 sf_offline_bundle_YYYYMMDD.zip (~600 MB)
        │ 加 manifest.json (SHA256) + INSTALL.txt + .sha256 校驗檔
        ▼
[3] 拷貝到 USB         + 解壓還是不解壓? (見下)
        │
        ▼
[4] USB 掃毒           進公司前必經, 公司資安要求
        │
        ▼
[5] USB 帶進機房       SF 主機插 USB
        │
        ▼
[6] SF 解壓 / 拷貝     到 C:\ClaudeHome\SFTP\
        │
        ▼
[7] 驗證 bundle 完整   .\scripts\verify_bundle.ps1
        │
        ▼
[8] 一鍵安裝           .\deploy\offline\install_offline.ps1
        │
        ▼
[9] 健康檢查           .\scripts\health_check.ps1
        │
        ▼
[10] USB 回收 / 銷毀    依公司資安政策
```

---

## 二、USB 申請

### 申請項目
- **容量**: 至少 **2 GB** (建議 8 GB, 預留之後更新版本)
- **規格**:
  - USB 3.0 以上 (拷貝快)
  - 公司既有的 加密 USB (BitLocker / IronKey) 優先 — 可降低資安風險
  - 沒有加密 USB → 用 FAT32 或 NTFS, 避免 exFAT 在舊機器不認

### 申請理由 (給主管 / 資安看)

```
申請項目: SF 中繼檔案交換主機 軟體分發 USB

用途說明:
- SF 主機建置需離線安裝, 約 600 MB 軟體 (SQL Express / Python / IIS 模組等)
- 公司內網無法直接下載 Microsoft / 開源軟體, 需走 USB 一次性帶入
- 安裝完成後, USB 內容退役, 不留個人手上

軟體內容 (全部公開可下載, 無授權問題):
- Microsoft SQL Server 2022 Express (~250 MB) - Microsoft 免費
- Python 3.11.9 (~25 MB) - 開源
- IIS URL Rewrite / ARR (~14 MB) - Microsoft 免費
- Visual C++ Redistributable (~25 MB) - Microsoft 免費
- NSSM (~400 KB) - 開源
- Python 套件 wheels (~80 MB) - 開源
- 公司專案程式碼 (~5 MB) - 公司資產

打包方式:
- 由 IT 在能上網的工作站打包成 zip + SHA256 校驗檔
- 拷貝到 USB 前先掃毒
- USB 上有 INSTALL.txt 寫使用說明

資安措施:
- 不含個資 / 客戶資料 / 公司機敏
- 所有檔案皆有 SHA256 校驗, 進公司後驗證確認未被竄改
- 安裝完畢, USB 退役交回 IT
```

---

## 三、外網工作站 — 打包

### 準備
1. 找一台**能上 Internet** 的工作站 (個人 NB / VDI / Jump host)
2. 安裝 **PowerShell 5.1+** 與 **Python 3.11** (Python 用來 pip download 抓 wheels)

### 取得專案
```powershell
# 從公司 git 或既有 share 取
git clone <SF repo URL> C:\ClaudeHome\SFTP
# 或
# Copy-Item \\fileserver\IT\SF\source\* C:\ClaudeHome\SFTP -Recurse
```

### 跑打包腳本
```powershell
cd C:\ClaudeHome\SFTP\deploy\offline
.\build_offline_bundle.ps1
```

預期輸出:
```
=== SF 離線 bundle 建構器 ===
[下載] Visual C++ Redistributable x64 (~25 MB)
[下載] SQL Server 2022 Express SSEI downloader (~5 MB)
       → 跑 SSEI 抓 SQL Express 完整離線版 (~250 MB)...
[下載] SQL Server Command Line Utilities (~6 MB)
[下載] URL Rewrite Module 2.1 (~7 MB)
[下載] Application Request Routing 3.0 (~7 MB)
[下載] Python 3.11.9 (~25 MB)
[下載] NSSM 2.24 (zip) (~400 KB)
[下載] Python 套件 wheels (~80 MB)

[Step 5] 產生 checksum + manifest...
[ok] manifest.json (含 142 個檔案的 SHA256)
[ok] INSTALL.txt

[Step 6] 打包成 zip
[ok] sf_offline_bundle_20260518.zip (~605 MB)
[ok] zip SHA256: a3f5b9c2d4e1f5g6...
```

### 拷貝到 USB

**選項 A: 直接拷貝 zip + 校驗檔** (推薦)
```
USB:\
├── sf_offline_bundle_20260518.zip          # ~605 MB
├── sf_offline_bundle_20260518.zip.sha256   # ~80 bytes (校驗檔)
└── README.txt                              # 給 IT 看的簡短指引 (見下)
```

**選項 B: 預先解壓, USB 上是攤平的檔案結構**
```
USB:\
├── installers\
├── python_wheels\
├── deploy\
├── scripts\
├── ...
├── manifest.json
└── INSTALL.txt
```

→ **推薦 A**, 因為:
- 單一檔, 拷貝快
- USB 上比較不會被 IT 不小心動到
- zip 本身 SHA256 可整體校驗

### 在 USB 根目錄產生 README.txt

```powershell
# 在打包完, 拷貝到 USB 後
@'
============================================================
 SF 離線安裝 USB
============================================================

請在 SF 主機 (Windows Server 2022) 上操作:

[1] 拷貝 zip 到本機 (USB 跑安裝可能很慢):
    Copy-Item .\sf_offline_bundle_*.zip C:\Temp\

[2] 校驗 zip 完整性:
    $expected = (Get-Content .\sf_offline_bundle_*.zip.sha256).Split(' ')[0]
    $actual = (Get-FileHash C:\Temp\sf_offline_bundle_*.zip -Algorithm SHA256).Hash
    if ($expected -eq $actual) { "OK" } else { "FAIL - 檔案損毀!" }

[3] 解壓到專案目錄:
    Expand-Archive C:\Temp\sf_offline_bundle_*.zip -DestinationPath C:\ClaudeHome\SFTP -Force

[4] 細部驗證 (檢查每個檔案的 SHA256):
    cd C:\ClaudeHome\SFTP
    .\scripts\verify_bundle.ps1

[5] 一鍵安裝:
    .\deploy\offline\install_offline.ps1

詳細 SOP: 解壓後 C:\ClaudeHome\SFTP\docs\deployment_sop.md
'@ | Set-Content -Path E:\README.txt -Encoding UTF8
```

---

## 四、USB 掃毒

進公司前**強制**掃毒:
1. 公司提供的掃毒站 (IT 大廳常有)
2. 自己工作站用 Defender 跑 `Start-MpScan -ScanPath E:\`
3. 線上 VirusTotal **不行** (檔案會被上傳)

掃毒 log 留底, 給資安看。

---

## 五、SF 主機端操作

### 1. USB 插上後拷貝到本機

```powershell
# 假設 USB 是 E:
Copy-Item E:\sf_offline_bundle_*.zip C:\Temp\
```

### 2. 校驗 zip 完整性

```powershell
cd C:\Temp
$expected = (Get-Content .\sf_offline_bundle_*.zip.sha256 -Raw).Trim().Split(' ')[0]
$actual = (Get-FileHash .\sf_offline_bundle_*.zip -Algorithm SHA256).Hash

if ($expected -eq $actual) {
    Write-Host "[OK] zip SHA256 一致" -ForegroundColor Green
} else {
    Write-Host "[FAIL] zip 損毀, 重拷貝" -ForegroundColor Red
    # 重新從 USB 拷
}
```

### 3. 解壓

```powershell
# 確保目錄存在
if (-not (Test-Path C:\ClaudeHome\SFTP)) {
    New-Item -Path C:\ClaudeHome\SFTP -ItemType Directory -Force | Out-Null
}

Expand-Archive C:\Temp\sf_offline_bundle_*.zip -DestinationPath C:\ClaudeHome\SFTP -Force
```

### 4. 細部驗證 (每個檔的 SHA256)

```powershell
cd C:\ClaudeHome\SFTP
.\scripts\verify_bundle.ps1
```

**預期輸出**:
```
=== Bundle 完整性驗證 ===
[ok] manifest 載入: sf_offline_20260518
    打包時間: 2026-05-18T14:32:18+08:00
    打包者:   CORP\IT.User @ IT-WS-01
    檔案數:   142

(進度條)
...

=== 驗證結果 ===
OK      : 142
FAIL    : 0
MISSING : 0
SKIPPED : 0

✓ bundle 完整, 可以繼續跑 install_offline.ps1
```

### 5. 一鍵安裝

```powershell
.\deploy\offline\install_offline.ps1
```

或第二階段 (公司 DB 已申請完):
```powershell
.\deploy\offline\install_offline.ps1 -DbMode CorpDB -CorpDBServer 'corp-sql01.internal,1433'
```

### 6. 健康檢查

```powershell
.\scripts\health_check.ps1
```

---

## 六、USB 回收

裝完後依公司資安政策:
1. USB 內容**清空** (Format 或 cipher /w:)
2. USB **回收** 給 IT
3. 或**重新格式化加密**, 留下次用
4. **不可帶回家** / **不可放抽屜**

---

## 七、常見問題

### Q1: 為什麼 zip SHA256 校驗 OK, 但 verify_bundle.ps1 卻有 FAIL?
A: zip 完整但解壓出錯。可能原因:
- 防毒軟體把某個 exe 刪了 (常見)
- 磁碟空間不足 (D: 至少 1 GB 空間給解壓)
- 解壓中斷
→ 把這些檔加進防毒例外, 重新解壓。

### Q2: USB 在 SF 主機認不出來?
A: SF 主機可能停用 USB (公司資安政策)。要走 IT 申請臨時開啟 USB port:
- 申請理由: SF 主機建置
- 時間: 1-2 天 (足夠安裝 + 驗證)
- 開啟期間: 不接其他用途, 不傳檔

### Q3: 公司禁止用 USB?
A: 替代方案:
- **網路傳檔**: 用公司既有的安全傳檔 (例如 SFTP / SharePoint / 內部 share)
- **DVD 燒錄**: 6xx MB 剛好一張 DVD
- **HTTPS 下載**: 在公司內網建一個 share, IT 從那邊拉

### Q4: 600 MB USB 拷貝很慢?
A:
- USB 3.0 約 30-60 秒
- USB 2.0 約 5-10 分鐘
- USB 3.0 + zip (不解壓) 比 USB 3.0 + 解壓再拷貝快很多

### Q5: 我可以更新 bundle 嗎?
A: 可以。重新跑 `build_offline_bundle.ps1` 會產生新版本 zip。舊版 USB 回收, 新版 USB 帶進去。新版本 install_offline.ps1 是 idempotent (重跑會跳過已裝)。

---

## 八、更新策略

| 變更類型 | 處理方式 |
|---|---|
| **程式碼 / 設定** (常改) | git pull 即可, 不用 USB |
| **Python 套件版本升** | 走公司 PyPI mirror (如果有), 或新打包 USB |
| **Microsoft 套件大版** (例 SQL Express 2025) | 重新打 USB 進公司 |
| **緊急 patch** | 個別檔走 SFTP / 安全傳檔 |

→ 99% 的更新可走 git, USB 只在重大版本升時用。

---

## 九、檢查清單 (列印給 IT 帶)

```
[ ] USB 已掃毒
[ ] 帶進公司前確認 USB 內容: zip + .sha256 + README.txt
[ ] SF 主機可連線 (RDP 或本機)
[ ] SF 主機磁碟空間: C: > 50 GB, D: > 100 GB
[ ] SF 主機已加入 AD 網域
[ ] SSL 憑證已準備 (.pfx)
[ ] 公司 NTP / SMTP / DBA 連絡人有
[ ] 防火牆審單已通

[拷貝] USB → C:\Temp\sf_offline_bundle_*.zip
[校驗] Get-FileHash 比對 .sha256
[解壓] Expand-Archive → C:\ClaudeHome\SFTP\
[驗證] verify_bundle.ps1 → 全 OK
[安裝] install_offline.ps1
[健康] health_check.ps1 → 全 OK
[USB ] 回收
```
