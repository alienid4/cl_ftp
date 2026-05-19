# SF 專案 SKILL — 工作流程規範

跟 Claude 合作開發 SF 專案的**強制紀律**, 確保每次互動都留下可追溯紀錄。

> 這份文件給 Claude 自己看 (將來再開新 session, 一進來就讀這個)
> 也給將來接手的人類看 (知道為什麼會有這套紀錄系統)

---

## 鐵律 1: 每個錯誤都進 `docs/dev-log/issues_log.md`

使用者一回報新錯誤, 立刻:
1. 新增到 `issues_log.md` 頂部 (編號遞增 #NNN)
2. **必填 9 欄位**: 發現日期 / 狀態 / 回報者 / 症狀 / 根本原因 / 解法 / 影響檔 / Commit / 驗證
3. 狀態用 4 種 emoji: 🆕 / 🔴 / 🟡 / ✅
4. 解決後**回頭更新**狀態與 Commit 欄位

❌ 不要靠記憶。❌ 不要只 git commit 不寫 issue。

---

## 鐵律 2: 每次重大進展寫 `docs/dev-log/dev_journal.md`

每次跟使用者完成一個段落 (不一定每個 commit):
1. 用日期分區塊
2. 條列當天/當次完成什麼
3. **寫「為什麼這樣做」**, 不只「做了什麼」
4. 對應 patch / issue / commit 編號

何謂「重大進展」:
- 跨檔架構決策
- 新增模組
- 解決長時間卡關的問題
- 跟使用者對齊重要決策後

---

## 鐵律 3: 每次有檔案修改都產生 Patch

**對應原則**:
- bug fix → 對應 `patches/v1.0.0.X/` (X 遞增)
- 新功能 → 對應 `patches/v1.X.0/` (中型) 或 `patches/v2.0.0/` (大型)

**Patch 必含 3 個東西**:
1. `PATCH_NOTE.md` (8 大欄位)
2. `apply.ps1` (idempotent + dry-run + 備份)
3. `files/` 鏡像專案結構

詳見 [patches/README.md](../../patches/README.md)

---

## 鐵律 4: `.ps1` 一律 UTF-8 with BOM

中文 Windows 系統的 Windows PowerShell 5.1 預設用 Big5 讀, 沒 BOM 會中文亂碼 → parser error。

每次 Write/Edit .ps1 後立刻補:
```powershell
$c = [System.IO.File]::ReadAllText($path)
[System.IO.File]::WriteAllText($path, $c, [System.Text.UTF8Encoding]::new($true))
```

並驗證:
```powershell
$err = $null
[System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$err)
$err.Count -eq 0  # 預期 True
```

---

## 鐵律 5: binary 絕對不進 git

`.gitignore` 已守住:
- `*.exe / *.msi / *.whl / *.iso / *.zip`
- `deploy/offline/sf_binaries/`
- `deploy/offline/installers/`
- `deploy/offline/python_wheels/`
- `*.pfx / *.pem / *.key`
- `.env / appsettings.json`

push 前可用 `git check-ignore -v <file>` 確認被擋。

---

## 鐵律 6: 真實主機 / 員工 / IP 全部 placeholder

Public repo 不寫:
- 真實主機名 (`AP-PRD-01` 改 `<ap-host>`)
- 真實員工 AD 帳號 (`CORP\zhang.ming` 改 `CORP\<user>`)
- 真實 IP (除 RFC1918 範例的 `10.x.x.x`)
- 真實部門編號
- 真實密碼 / token / 憑證

mockup 中的「王主管 / 張小明」明顯是 placeholder 名, OK。

---

## 鐵律 7: 大檔走別的通道

`> 100 MB` 不該 push git, `> 10 MB` 警示 (放 Release 或 server)。

bundle 應該:
- git: 程式碼 + 腳本 + 文件 (~5 MB)
- GitHub Release: 不附 binary (only source tag)
- 343 MB zip: 使用者的 server / USB / OneDrive

---

## 鐵律 8: 每次互動結尾**自我檢查**

提交工作前自問:
- [ ] 有新錯誤? 進 `issues_log.md` 了?
- [ ] 有修檔? 產生 `patch` 了?
- [ ] .ps1 有 BOM?
- [ ] git add 沒誤加 binary?
- [ ] 真實資訊 placeholder 化?
- [ ] `dev_journal.md` 有追加?

---

## 互動模式

### 使用者提供錯誤資訊 → 我做的事
1. **立即診斷** + 給 workaround (#003 NSSM 503 之類)
2. 修檔 + 加 BOM + 驗證語法
3. **新增 issue** 到 issues_log.md (狀態 = 🆕 → 🟡 → ✅)
4. **新增 patch** 到 patches/vX.X.X.X/
5. git commit + push
6. **更新 journal** 簡短一筆
7. 告訴使用者**用哪個 patch / 怎麼套用**

### 使用者提出新需求 → 我做的事
1. 對齊需求 (問澄清問題)
2. 寫設計 / 修文件
3. 寫程式碼 / 腳本
4. **同步 plan + mockup + 文件**
5. 加 BOM, push
6. **journal 追加**重大決策

### 使用者問純問題 → 我做的事
1. 答覆
2. 如果答覆內涉及新規範 → 也寫進 SKILL / journal

---

## 文件導航 (給將來接手者)

第一次接手讀這幾個檔的順序:

1. [README.md](../../README.md) — 整體 5 分鐘
2. [架構圖](../architecture-v2.html) — 視覺化 (用瀏覽器開)
3. [本檔 SKILL](skill_sf_workflow.md) — 規範 5 分鐘
4. [issues_log.md](issues_log.md) — 知道踩過什麼坑
5. [dev_journal.md](dev_journal.md) — 時間軸
6. [patches/README.md](../../patches/README.md) — 修補規範
7. [docs/deployment_sop.md](../deployment_sop.md) — 部署 SOP

讀完約 30-45 分鐘, 可上手。

---

## 統計 / 量化指標

每月一次自我檢核 (在 dev_journal 寫):

| 指標 | 目標 | 當前 |
|---|---|---|
| Issues 解決率 | > 80% | 78% (7/9) |
| Patch 涵蓋率 | 每個 fix 都有 patch | 100% (1/1) |
| .ps1 BOM 覆蓋率 | 100% | 100% (25/25) |
| Plan 是否反映現況 | 是 | 是 (last update: 2026-05-19) |
| README 連結是否最新 | 是 | 是 |

---

## 不要做的事

- ❌ 「我記得之前有解過」 — 翻 issues_log, 不要記憶
- ❌ commit 不寫 journal
- ❌ fix 不出 patch (除非是純文件改動)
- ❌ 用 UTF-8 no BOM 寫 .ps1
- ❌ 把使用者 IP / 帳號寫進 public repo
- ❌ 一個 bug 重複踩 (應該已記 issue, 直接套既有解)
