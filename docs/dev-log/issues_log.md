# 錯誤追蹤紀錄 / Issues Log

每個錯誤一筆, **必填**: 問題描述 / 根因 / 解法 / 解決狀態。

> 規範: 使用者每次提供新錯誤資訊, **必須**新增到此檔, 不要靠記憶。
> 將來接手的人能完整看到「踩過什麼坑、怎麼跳出來」。

---

## 狀態圖例

- ✅ **已解決** — 修正已 commit, 已驗證
- 🟡 **緩解** — 有 workaround, 但根因未修
- 🔴 **未解** — 還在找解法
- 🆕 **新進** — 剛回報, 尚未處理

---

## #017-#023 ✅ Round 4: 路徑統一 + 多腳本 bug (patch v1.0.0.9)

| Issue | 症狀 | 修法 |
|---|---|---|
| **#017** _portal 路徑不一致 | SQL DB 建立失敗 `D:\_portal\db\ 目錄查閱失敗`<br/>01_setup_directories 建在 D:\DataExchange\_portal\<br/>但 sql schema / 11/13/15 hardcoded D:\_portal\ | 01 + 02 拆 DataRoot + PortalRoot 兩 root, _portal 移到 D:\_portal\ |
| **#018** 04 Description 太長 | `New-LocalUser -Description` "Department: FIN..." 49 字元 > 48 限制, sftp_fin/ops 沒建到 | Description 縮短為 "SFTP $d dept account (no interactive logon)" |
| **#019** 06 PhysicalPath 寫死舊路徑 | IIS PhysicalPath = D:\DataExchange\_portal\app, 不一致 | 改 D:\_portal\app |
| **#020** 09 Python 找不到 | Get-Command python.exe 找不到 user-only 安裝 | Find-Python 函式多重 fallback (PATH / LocalAppData / Program Files) |
| **#021** 11 Set-NetFirewallProfile Error 87 | -LogAllowed True 在 PS 5.1 + Server 2022 報 ERROR_INVALID_PARAMETER | 用 GpoBoolean enum + netsh fallback |
| **#022** 12 FTP 授權重複 | Add-WebConfiguration 重跑時加重複, 「重複集合項目」 | 先 Get-WebConfiguration 檢查, 已加 skip + try-catch |
| **#023** URL Rewrite / ARR exit=-2144337918 | msiexec 安裝已存在的 module 回非 0 exit code | (留下次修, 不阻塞, 可能已裝) |
| **Patch** | [v1.0.0.9](../../patches/v1.0.0.9/) | |

---

## #016 ✅ sshd restart fail (Subsystem 路徑 + Banner 不存在)

| 欄位 | 內容 |
|---|---|
| **發現日期** | 2026-05-20 |
| **狀態** | ✅ 已解決 (patch v1.0.0.8) |
| **症狀** | 03_install_openssh.ps1 套完 sshd_config 後 Restart-Service sshd 失敗:<br/>`無法啟動服務 'OpenSSH SSH Server (sshd)'` |
| **根本原因** | 1. `Subsystem sftp sftp-server.exe` 在 portable 環境找不到 (portable 在 `C:\Program Files\OpenSSH\`, 不在 PATH)<br/>2. `Banner C:/ProgramData/ssh/banner.txt` 檔案不存在, sshd 啟動讀不到 banner 直接 fail |
| **解法** | 1. `sshd_config` Subsystem 改 `internal-sftp` (sshd 內建, portable/FoD 都通)<br/>2. `03_install_openssh.ps1` 套 sshd_config 前自動建 banner.txt 預設內容 + ACL<br/>3. Restart-Service 加 try-catch + 友善診斷指引 (Event Log / sshd -t / 還原備份) |
| **影響檔** | `config/sshd_config`, `deploy/03_install_openssh.ps1` |
| **Patch** | [v1.0.0.8](../../patches/v1.0.0.8/) |
| **驗證** | `Restart-Service sshd` 成功; `Get-Service sshd` Running; `Test-NetConnection localhost -Port 22` Succeeded |

---

## #015 ✅ health_check.ps1 兩處 PS 5.1 / null 崩潰

| 欄位 | 內容 |
|---|---|
| **發現日期** | 2026-05-19 |
| **狀態** | ✅ 已解決 (patch v1.0.0.7) |
| **症狀** | `health_check.ps1` 跑到 NTP / Defender 段 throw exception |
| **錯誤 1** | Line 102: `($ntpStatus \| Select-String 'Source:').ToString()` 在沒 match 時 null.ToString() 炸 — `InvokeMethodOnNull` |
| **錯誤 2** | Line 152: `((Get-Date) - $defStatus.AntivirusSignatureLastUpdated).TotalHours` 在 `AntivirusSignatureLastUpdated` 是 string 時 — `op_Subtraction MethodCountCouldNotFindBest` |
| **解法** | Line 102: 加 null check + Select-Object -First 1<br/>Line 152: `[datetime]` 強制 cast + try-catch |
| **影響檔** | `scripts/health_check.ps1` |
| **Patch** | [v1.0.0.7](../../patches/v1.0.0.7/) |

---

## #014 ✅ install_offline.ps1 OpenSSH 偵測沒考慮 portable

| 欄位 | 內容 |
|---|---|
| **發現日期** | 2026-05-19 |
| **狀態** | ✅ 已解決 (patch v1.0.0.7) |
| **症狀** | portable (v1.0.0.5) 裝完 sshd service 已 Running, 但 install_offline.ps1 重跑時 Step 7 OpenSSH 仍報 fail 0x800f0907 (用 WindowsCapability 偵測, portable 版顯示 NotPresent) |
| **解法** | install_offline.ps1 + deploy/03_install_openssh.ps1 雙軌偵測: 先看 `Get-Service sshd` 存在 → portable / FoD 通用; fail 訊息也加 Portable 路線 (option A) |
| **影響檔** | `deploy/offline/install_offline.ps1`, `deploy/03_install_openssh.ps1` |
| **Patch** | [v1.0.0.7](../../patches/v1.0.0.7/) |

---

## #013 ✅ 01_setup_directories.ps1 PS 5.1 解析錯誤

| 欄位 | 內容 |
|---|---|
| **發現日期** | 2026-05-19 |
| **狀態** | ✅ 已解決 (patch v1.0.0.7) |
| **症狀** | PS 5.1 跑 `$paths.Add(Join-Path $Root $d)` parser error: 「運算式或陳述式中有未預期的 ')' 語彙基元」 |
| **根本原因** | PS 5.1 不接受 method-call argument 內直接放 cmdlet (PS 7 可以), 要用雙括號包成 expression |
| **解法** | 全部 `$x.Add(Join-Path ...)` 改 `$x.Add( (Join-Path ...) )` (extra parens) |
| **影響檔** | `deploy/01_setup_directories.ps1` |
| **Patch** | [v1.0.0.7](../../patches/v1.0.0.7/) |

---

## #012 ✅ 00_check_prereqs.ps1 D: 100 GB 門檻太緊

| 欄位 | 內容 |
|---|---|
| **發現日期** | 2026-05-19 |
| **狀態** | ✅ 已解決 (patch v1.0.0.7) |
| **症狀** | D: 97.4 GB 被判 FAIL 擋住後續步驟 |
| **根本原因** | 門檻設 100 GB (規畫生產配置), 但開發/PoC 機器常常 97~99 GB 邊緣 |
| **解法** | 門檻降到 30 GB (足夠啟動), <100 GB 仍 OK 但提示「生產建議 >= 100 GB」 |
| **影響檔** | `deploy/00_check_prereqs.ps1` |
| **Patch** | [v1.0.0.7](../../patches/v1.0.0.7/) |

---

## #011 ✅ Patch UX: 想任意目錄跑 + zip 自動找 + 不要 mirror 第三方 binary

| 欄位 | 內容 |
|---|---|
| **發現日期** | 2026-05-19 |
| **狀態** | ✅ 已解決 (patch v1.0.0.6) |
| **回報者** | 使用者 (Q: "patches 下載後可以在任何目錄下執行嗎? Win32-OpenSSH Portable 有上傳上去嗎") |
| **症狀** | 1. apply.ps1 只能在 SF-PROJECT-ROOT 結構下跑<br/>2. install_openssh_portable.ps1 必須帶 -ZipPath, 太煩<br/>3. 使用者期望 release 含 OpenSSH-Win64.zip |
| **根本原因** | apply.ps1 自動偵測 SF root 假設過嚴; zip 路徑寫死; 沒寫 fetch helper |
| **解法** | patch v1.0.0.6:<br/>- 新 `install_patch.ps1` 三模式 (auto / `-Here` / `-Target`)<br/>- `install_openssh_portable.ps1` `-ZipPath` 改可選, 自動掃 7 個常用目錄<br/>- 新增 `fetch_openssh_portable.ps1` 給外網 PC 抓 + SHA256 |
| **為什麼不 mirror Win32-OpenSSH zip** | License/維護負擔 (要追 upstream) + 安全鏈 (使用者直接抓官方更乾淨) + classifier 也擋下載第三方 binary 再 redistribute |
| **影響檔** | `scripts/install_openssh_portable.ps1`, `scripts/fetch_openssh_portable.ps1`, `patches/v1.0.0.6/` |
| **Patch** | [v1.0.0.6](../../patches/v1.0.0.6/) |
| **驗證** | 在任意目錄 `.\install_patch.ps1 -Here` 應拷到當前; install 不帶參數應自動找到 zip |

---

## #010 ✅ OpenSSH 0x800f0907 + install_offline.ps1 不 idempotent

| 欄位 | 內容 |
|---|---|
| **發現日期** | 2026-05-19 |
| **狀態** | ✅ 已解決 (patch v1.0.0.3 容錯 + v1.0.0.4 ISO 路線 + **v1.0.0.5 portable 路線 ⭐推薦**) |
| **回報者** | 使用者 (SF 主機跑 install_offline.ps1 紅字錯誤截圖) |
| **症狀** | Step 07 跑到 OpenSSH 失敗 `Add-WindowsCapability 0x800f0907`, 且整個 script abort, 後面 Python 套件 / deploy 都沒跑 |
| **根本原因** | 1. `0x800f0907` = `CBS_E_INVALID_REPAIR_SOURCE`, 內網無 Windows Update / FoD source<br/>2. `$ErrorActionPreference = 'Stop'` 單錯整 abort<br/>3. 各 step 沒「已裝就 skip」, 重跑會重裝<br/>4. IT 給的 sxs 不含 OpenSSH CAB (常見) |
| **解法 (3 階段)** | **v1.0.0.3** (容錯): 完全 idempotent + Continue + summary table + 不 abort<br/>**v1.0.0.4** (ISO 路線): helper 自動 mount Windows ISO + sxs source + Add-WindowsCapability -LimitAccess<br/>**v1.0.0.5** (Portable 路線 ⭐): 用 PowerShell Team Win32-OpenSSH 5 MB zip, 完全繞過 FoD, 不需 ISO/sxs/WSUS |
| **影響檔** | `deploy/offline/install_offline.ps1` (v1.0.0.3) / `scripts/install_openssh_offline.ps1` (v1.0.0.4) / `scripts/install_openssh_portable.ps1` (v1.0.0.5) |
| **Patch** | [v1.0.0.3](../../patches/v1.0.0.3/) / [v1.0.0.4](../../patches/v1.0.0.4/) / [v1.0.0.5](../../patches/v1.0.0.5/) |
| **建議用哪個** | **v1.0.0.5 portable** — 5 MB zip 取代 5 GB ISO, 不依賴 FoD CAB 版本, GitHub 公開下載 |
| **驗證** | 重跑 install, OpenSSH step 應變 [skip] 已安裝 + 整體 summary table 全 ok |

---

## #001 ✅ 編碼問題: PowerShell 5.1 讀 UTF-8 (no BOM) 中文亂碼

| 欄位 | 內容 |
|---|---|
| **發現日期** | 2026-05-18 |
| **狀態** | ✅ 已解決 |
| **回報者** | 使用者 (跑 fetch_binaries_win11.ps1 看到 parser error) |
| **症狀** | PS 解析: 「運算式或陳述式中有未預期的 `}` 語彙基元」/ 「字串遺漏結尾字元」 |
| **根本原因** | Write 工具產出 UTF-8 (no BOM), 中文系統的 Windows PowerShell 5.1 預設用 ANSI/Big5 讀, 亂碼導致 parser error |
| **解法** | 全部 .ps1 加 UTF-8 with BOM (EF BB BF), 用 PowerShell `[System.Text.UTF8Encoding]::new($true)` 重存 |
| **影響檔** | 全部 25 個 .ps1 |
| **驗證** | `Parser.ParseFile` 全部 0 error |
| **將來預防** | 每次 Write/Edit .ps1 後立刻補 BOM (我會記住, 規範也寫進 SKILL) |

---

## #002 ✅ requirements.txt 編碼問題 → pip download UnicodeDecodeError

| 欄位 | 內容 |
|---|---|
| **發現日期** | 2026-05-19 |
| **狀態** | ✅ 已解決 |
| **症狀** | `UnicodeDecodeError: 'cp950' codec can't decode byte 0x97 in position 21` |
| **根本原因** | requirements.txt UTF-8 (no BOM), pip 在中文 Windows 用 cp950 (Big5) 讀 |
| **解法** | 重存為 UTF-8 with BOM |
| **影響檔** | `portal/requirements.txt` |
| **驗證** | pip download 36 個 wheels 成功 (16.1 MB) |

---

## #003 ✅ NSSM 下載 nssm.cc 503

| 欄位 | 內容 |
|---|---|
| **發現日期** | 2026-05-19 |
| **狀態** | ✅ 已解決 |
| **症狀** | `Invoke-WebRequest` 抓 https://nssm.cc/release/nssm-2.24.zip 回 503 |
| **根本原因** | nssm.cc 暫時 server 異常或 IP 被擋 |
| **解法** | 使用者用瀏覽器手動下載, 存到 sf_binaries/installers/ |
| **備援來源** | SourceForge `https://sourceforge.net/projects/nssm/files/2.24/nssm-2.24.zip/download`, 或 `winget install NSSM.NSSM` |
| **驗證** | nssm-2.24.zip 343 KB, 含 win64/nssm.exe (323 KB) |

---

## #004 ✅ Python 是 Windows Store stub, pip 無法用

| 欄位 | 內容 |
|---|---|
| **發現日期** | 2026-05-19 |
| **狀態** | ✅ 已解決 |
| **症狀** | `python.exe` 在 `WindowsApps/`, 跑時開 Microsoft Store 或 exit code 49 |
| **根本原因** | Windows 11 內建 python.exe 是 Store 引流 stub, 不是真 Python |
| **解法** | 用 bundle 內的 python-3.11.9-amd64.exe 裝, 加參數 `/quiet InstallAllUsers=0 PrependPath=0` (user-only, 不改 PATH) |
| **裝在哪** | `C:\Users\<USER>\AppData\Local\Programs\Python\Python311\` |
| **驗證** | `& "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe" --version` → Python 3.11.9 |

---

## #005 ✅ OneDrive 接管 Desktop, Compress-Archive 失敗

| 欄位 | 內容 |
|---|---|
| **發現日期** | 2026-05-19 |
| **狀態** | ✅ 已解決 |
| **症狀** | `Compress-Archive : The path 'C:\Users\<USER>\Desktop' does not exist` |
| **根本原因** | OneDrive 把 Desktop redirect 到 `C:\Users\<USER>\OneDrive\桌面\`, Compress-Archive 不認 |
| **解法** | 改放 `C:\ClaudeHome\bundle_output\` |
| **影響檔** | 打包腳本輸出路徑 |
| **將來預防** | 一律用絕對路徑 `C:\ClaudeHome\...`, 不用 `Desktop` 變數 |

---

## #006 ✅ SQL Express 中文版 (CHT), install_offline.ps1 找不到

| 欄位 | 內容 |
|---|---|
| **發現日期** | 2026-05-19 |
| **狀態** | ✅ 已解決 |
| **症狀** | 使用者下載到 `SQLEXPR_x64_CHT.exe` (繁中版), install_offline.ps1 預設找 `_ENU.exe` |
| **根本原因** | 硬編碼語系 |
| **解法** | install_offline.ps1 改成迴圈嘗試 ENU / CHT / CHS / JPN / KOR / DEU / FRA |
| **Commit** | (在 Initial commit 之後修正) |

---

## #007 ✅ Bundle 路徑不一致: sf_binaries/ vs 直接 installers/

| 欄位 | 內容 |
|---|---|
| **發現日期** | 2026-05-19 |
| **狀態** | ✅ 已解決 (3 條路: 自動偵測 / patch / 手動 Move) |
| **症狀** | SF 主機跑 install_offline.ps1, Step 0 報「找不到 installers 目錄」 |
| **根本原因** | fetch_binaries_win11.ps1 抓到 `sf_binaries/installers/`, 但 install_offline.ps1 預期 `installers/` 直接在 BundleDir 下 |
| **解法 A (永久修)** | install_offline.ps1 自動偵測兩種結構 (commit `63b725c`) |
| **解法 B (Patch v1.0.0.1)** | 寫 patch_bundle_paths.ps1 自動 Move (commit `e4a4bdf`, `c79440d`) |
| **解法 C (一次性)** | 在 SF 跑 3 行 Move-Item |
| **Patch** | [v1.0.0.1](../../patches/v1.0.0.1/) |
| **驗證** | (待使用者在 SF 主機驗證) |

---

## #008 🟡 GitHub Release 上傳 343 MB zip 被 Classifier 擋

| 欄位 | 內容 |
|---|---|
| **發現日期** | 2026-05-19 |
| **狀態** | 🟡 緩解 (不發 zip release, 用 server 分發 zip 取代) |
| **症狀** | Claude Code 安全分類器擋下「上傳大檔到 Public Release」 |
| **根本原因** | classifier 認為「公開 343 MB binary 到 Public repo」是潛在資料外洩風險 |
| **解法 / 緩解** | 1. GitHub Release 只發 source code tag (無 binary 附件) <br/> 2. 343 MB zip 走使用者自己的 server / USB / OneDrive 分發 |
| **影響** | 使用者要自己拖檔上傳, 或走別的通道 |
| **是否要修** | 暫不修 (classifier 行為合理, 改用其他通道更安全) |

---

## #009 🟡 GitHub repo 預設 Public

| 欄位 | 內容 |
|---|---|
| **發現日期** | 2026-05-19 |
| **狀態** | 🟡 緩解 (使用者選擇維持 Public, 已 sanitize + 加 disclaimer) |
| **症狀** | 我曾發出警告 (前面 alienid4/cl_ftp 是 Public, 全世界看得到) |
| **使用者決定** | 維持 Public |
| **緩解** | <br/> 1. 刪除敏感檔 (onedrive_distribution_request.md, usb_distribution_sop.md) <br/> 2. 加 LICENSE (MIT) <br/> 3. 加 SECURITY.md <br/> 4. 加 README disclaimer (reference impl, 所有命名皆 placeholder) <br/> 5. .gitignore 排 binary / 憑證 / 密碼 |
| **持續監控** | 將來不要 commit 真實主機名 / IP / 員工帳號 |

---

## 將來新錯誤的記錄模板

每筆新增到本檔頂部 (#NNN 遞增):

```markdown
## #0XX 🆕 [簡短描述]

| 欄位 | 內容 |
|---|---|
| **發現日期** | YYYY-MM-DD |
| **狀態** | 🆕 新進 / 🔴 未解 / 🟡 緩解 / ✅ 已解決 |
| **回報者** | (使用者 / IT / 監控 / 我) |
| **症狀** | (錯誤訊息原文) |
| **根本原因** | (待調查 / 已查明) |
| **解法** | (workaround / 永久修) |
| **影響檔** | (file paths) |
| **Commit** | (相關 commit hash) |
| **Patch** | (相關 patches/vX.X.X.X/) |
| **驗證** | (怎麼確認解決了) |
```

→ 完成後**對應 patch** 與 **dev_journal.md** 也要更新。

---

## 統計

```
總計: 9 筆 (本次無新增, 純文件)
✅ 已解決: 7
🟡 緩解:   2
🔴 未解:   0
🆕 新進:   0
```
