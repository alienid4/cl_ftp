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

## 鐵律 10: Pull 模式優於 Push 打包

部署到「他人的環境」時, **永遠先問**:
1. 「他的環境有沒有 mirror / registry?」
2. 「能不能讓他自己 pull?」
3. **打包 binary 給他裝是最後手段**

### 為什麼

| 反模式 (push) | 正模式 (pull) |
|---|---|
| 我在 A 環境 (Rocky 9.7) 打 RPM bundle | 他主機 (RHEL 9.6) 從公司 mirror pull |
| dnf download --alldeps 抓 311 個 RPM | dnf install 自己解 dep, 抓 ~50 個 |
| 必撞 file conflict (版本差異) | 不會 conflict |
| 每撞坑加 EXCLUDE, patch 累積無底洞 | 一次到位 |

### SF 專案血淚教訓

v1.x Windows: 打 .zip 帶 .exe / .msi → NSSM 503 / IIS / wheels / sshd_config 一連串坑 (10 個 patch)
v2.0 RHEL bundle: 打 .tar.gz 帶 .rpm → file conflict 連環坑 (10 個 patch)

→ 兩次都因為 **打包機 ≠ 目標機**, 必踩坑。
→ 改 pull (從公司 mirror) 一次到位, 不用 EXCLUDE_PATTERN 打 10 次補丁。

### 決策樹

```
要部署到他人環境
       ↓
他有 yum mirror / pypi mirror / container registry?
       │
   是  │  否 (才打 bundle)
       ↓
讓他 pull → 完工
```

---

## 鐵律 11: 評估「公司既有基礎設施」優先

**開工前必問** (寫進 runbook prerequisite):

```markdown
## 環境問卷 (給公司 IT)

1. 內網 yum/dnf mirror? URL ____
2. PyPI mirror / Nexus? URL ____
3. Container registry (Harbor/Nexus/GitLab)? URL ____
4. AD domain / LDAP? domain ____
5. 內部 GitHub / GitLab? URL ____
6. 跳板機 (jumphost)? IP ____
7. NTP server? IP ____
8. SMTP relay? IP ____
9. Backup server? path ____
10. 是否允許 podman/docker?
```

90% 公司有 1, 4, 7, 8, 9 (基本維運). 沒有的話自建, **不要重複造輪子**。

### 對應 SF 專案

開工前沒問, 結果:
- 假設「無外網」→ 打 bundle → file conflict 連環
- 假設「沒 AD」→ 寫一堆 LDAP integration → PAM 不確定
- 假設「沒 SMTP」→ 自寫 mail relay 設定 → 公司其實有

問完答案再選方案, 省 50% 時間。

---

## 鐵律 8: 每次互動結尾**自我檢查**

提交工作前自問:
- [ ] 有新錯誤? 進 `issues_log.md` 了?
- [ ] 有修檔? 產生 `patch` 了?
- [ ] .ps1 有 BOM?
- [ ] git add 沒誤加 binary?
- [ ] 真實資訊 placeholder 化?
- [ ] `dev_journal.md` 有追加?
- [ ] **給使用者跑的指令進了 `docs/runbook/` 了? (鐵律 9)**

---

## 鐵律 9: 給使用者跑的指令**只給 GitHub URL, 不在 chat inline**

### 核心原則 (使用者公司限制)

**公司 DLP 可能擋從 chat 複製內容到公司 PC**, 使用者只能從 **GitHub 公開 URL** 取得指令。

→ chat 訊息 **不寫具體指令**, 只寫:
1. **「跑這個 URL」+ 一條 URL**
2. 簡短解釋這個 script 做什麼

### 鐵律 9.1: 即時診斷指令也要進 `notes/note_<date>_<version>.md` (USER 2026-05-21 強化)

當情境是 **「跑這 3 行查問題」**, **「貼一下 systemctl 輸出」** 這種臨時診斷:

❌ 不能直接在 chat 列 systemctl / journalctl / tail / ss / curl 指令
✅ 寫進 `notes/note_<YYYYMMDD>_<version>.md`, chat 只給 URL

**命名規範**:
```
notes/note_<YYYYMMDD>_<version>.md
```

例:
- `notes/note_20260521_v2.2.3.md` — Portal 起不來時的 3 個診斷指令
- `notes/note_20260522_v2.2.5.md` — SFTP 測不通時的查法

**內容結構**:
```markdown
# Note <日期> <版本> — <簡短主題>

## 情境
(USER 上次跑到哪、失敗訊息)

## N 個診斷指令 (依序跑)
1. ```
   <bash 指令>
   ```
   預期看到 X, 看到 Y 代表 Z 原因

## 把結果截圖回報

## 對應版本表 (TBD 下一版要修啥)
```

**對應流程**:
```
USER 卡關回報   →   Claude 寫 note      →   commit + push
                                              ↓
                                       chat 只給 URL
                                              ↓
                                       USER 開 URL 看指令
                                              ↓
                                       SF 跑、回報結果
                                              ↓
                                       Claude 看結果 → 修 fix_portal 下一版
```

### 反例 (我不要做的)

```
❌ chat 訊息:
"跑這 5 行:
   sudo dnf install -y nginx postgresql ...
   git clone https://...
   cd /opt/sf
   sudo chmod +x ...
   sudo ./install_all.sh
"
```

→ 使用者無法複製 (公司擋)。

### 正例 (應該做的)

```
✅ chat 訊息:
"跑這個:
   https://github.com/alienid4/cl_ftp/raw/main/deploy-rhel/install_online.sh

它會自動 dnf install + clone + deploy。"
```

→ 使用者開 URL → 看 raw 內容 → 從 GitHub 複製。

### 對應流程

```
1. 我想給使用者跑指令
2. 寫成 .sh / .ps1 script
3. commit + push 到 GitHub
4. chat 只給 URL
5. 同步寫 runbook 記錄 (鐵律 9 原本要求)
```

### 例外 (極少數)

- 純解釋性概念 (「這個指令對應 Linux 的 X」) → OK
- 1 行純查詢 (`systemctl status sshd`) → OK
- 任何 > 3 行 + 含敏感操作 (sudo / install / 寫檔) → **必須走 GitHub**

### 命名規範

| 用途 | 位置 | URL 範例 |
|---|---|---|
| 一鍵 installer | `deploy-rhel/install_*.sh` | `https://github.com/.../deploy-rhel/install_online.sh` |
| Patch apply | `patches/v.../runpatch_v.sh` | `https://github.com/.../patches/v2.1.0/runpatch_v2.1.0.sh` |
| 最新版指向 | `release-zip/latest-*.sh` | `https://github.com/.../release-zip/latest-install.sh` |
| 一次性 helper | `scripts/<topic>.sh` | `https://github.com/.../scripts/diagnose_portal.sh` |

---

## 鐵律 9-OLD: 每次給使用者跑的「PowerShell 指令套組」進 `docs/runbook/`

使用者問「我下一步做什麼」、「怎麼跑」、「貼什麼指令」 →
我給的指令**不能只在對話裡丟過去就算**, 必須:

1. **同步寫進 `docs/runbook/v<patch-版本>_<YYYYMMDD>_<HHMM>_<topic>.md`**
2. **更新 `docs/runbook/README.md` 索引**
3. **commit + push GitHub**
4. **回應使用者時, 同時給對話的指令 + GitHub URL** (兩條備援)

### 命名規則

```
v<patch-版本>_<YYYYMMDD>_<HHMM>_<topic>.md
```

例:
- `v1.0.0.10_20260520_0830_linux_user_poc.md`
- `v1.0.0.11_20260521_1400_fix_https_cert.md`

### Runbook 必含 6 段

1. **元資料表** — 版本 / 日期 / 對象 / 預期結果 / 耗時
2. **前提條件** — checklist
3. **操作步驟** — 照順序的 PowerShell, 複製貼用
4. **預期結果** — 跑完應該看到什麼
5. **故障排除** — 對應 Linux 等價物 (若使用者是 Linux 背景)
6. **附錄** — 替代方案 (例: 無外網時怎辦)

### 為什麼這條重要

| 沒這條 | 有這條 |
|---|---|
| 使用者問同樣的事三次, 我答三次 | 第二次直接給 URL |
| 同事接手要問使用者 | 同事自己看 runbook 跑 |
| 過 1 個月使用者忘了上次怎麼做 | runbook 留 audit 紀錄 |
| 對話被 compact 後指令消失 | git 永久保存 |

### 例外: 不用進 runbook 的情況

- 純解釋性回答 (「這個概念是什麼意思」)
- 一次性除錯 (使用者貼錯字, 我說「改成 X 就好」)
- < 3 行的微小指令

判斷標準: 「下次跑同樣場景, 還會需要這串指令嗎?」是 → runbook。

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

### 使用者要求跑 PowerShell 指令 → 我做的事 ⭐ 新增
1. 在對話中直接給指令 (使用者立即可貼)
2. **同時** 寫 `docs/runbook/v<patch>_<YYYYMMDD>_<HHMM>_<topic>.md`
3. 更新 `docs/runbook/README.md` 索引
4. git commit + push
5. 回應使用者時, 給對話指令 + GitHub URL

判斷「要不要寫 runbook」: 下次同樣場景再做一次, 還需要這串指令嗎? 是 → 寫。

---

## 文件導航 (給將來接手者)

第一次接手讀這幾個檔的順序:

1. [README.md](../../README.md) — 整體 5 分鐘
2. [架構圖](../architecture-v2.html) — 視覺化 (用瀏覽器開)
3. [本檔 SKILL](skill_sf_workflow.md) — 規範 5 分鐘
4. [LINUX_USER_GUIDE.md](../LINUX_USER_GUIDE.md) — Linux 用戶速查 (Linux ↔ Windows 對照)
5. [issues_log.md](issues_log.md) — 知道踩過什麼坑
6. [dev_journal.md](dev_journal.md) — 時間軸
7. [patches/README.md](../../patches/README.md) — 修補規範
8. [runbook/README.md](../runbook/README.md) — 操作 SOP 歷史紀錄 ⭐
9. [docs/deployment_sop.md](../deployment_sop.md) — 部署 SOP

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
- ❌ **給使用者跑的指令只在對話裡, 沒進 `docs/runbook/`** (鐵律 9)
