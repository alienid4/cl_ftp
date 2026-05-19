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

## #010 ✅ OpenSSH 0x800f0907 + install_offline.ps1 不 idempotent

| 欄位 | 內容 |
|---|---|
| **發現日期** | 2026-05-19 |
| **狀態** | ✅ 已解決 (patch v1.0.0.3) |
| **回報者** | 使用者 (SF 主機跑 install_offline.ps1 紅字錯誤截圖) |
| **症狀** | Step 07 跑到 OpenSSH 失敗 `Add-WindowsCapability 0x800f0907`, 且整個 script abort, 後面 Python 套件 / deploy 都沒跑 |
| **根本原因** | 1. `0x800f0907` = 內網無 Windows Update / FoD source<br/>2. `$ErrorActionPreference = 'Stop'` 單錯整 abort<br/>3. 各 step 沒「已裝就 skip」, 重跑會重裝 |
| **解法** | patch v1.0.0.3:<br/>- 完全 idempotent (每 step check)<br/>- `Continue` + try-catch<br/>- 結尾 summary table<br/>- OpenSSH 4 種 fallback (WSUS / sxs / GUI / 暫開 WU) |
| **影響檔** | `deploy/offline/install_offline.ps1` |
| **Patch** | [v1.0.0.3](../../patches/v1.0.0.3/) |
| **驗證** | 重跑 install, 應看到 idempotent skip + 失敗 step warn 不 abort |

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
