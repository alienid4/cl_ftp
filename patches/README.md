# Patches 目錄 — Patch 管理規範

每次發現問題 / 修 bug, **都要建立對應的 patch 目錄**, 不要只 git commit 完事。
這樣已下載 zip 的 SF 主機才能拿到單獨的 patch 套用, 不用整個重灌。

---

## 雙分支策略 (v1.x 與 v2.x 並存)

| 分支 | 平台 | 狀態 | 目錄 |
|---|---|---|---|
| **v1.x.x** | Windows Server 2022 | maintenance | `deploy/`, `scripts/*.ps1`, `config/sshd_config` |
| **v2.x.x** ⭐ | RHEL 8/9 | 主開發 | `deploy-rhel/`, `config/sshd_config_linux`, `config/nginx/`, `config/sssd/`, `config/samba/` |

共用: `portal/` (Flask app), 規畫文件, 主管圖, 整體規範。

---

## 版本號規則

| 版本 | 何時用 | 範例 |
|---|---|---|
| `v1.0.0.X` / `v2.0.0.X` | bug fix patch (4 段) | v1.0.0.1, v2.0.0.1 |
| `v1.X.0` / `v2.X.0` | 中型改版 (新功能, 3 段) | v2.1.0 (加 PAM) |
| `v2.0.0` (主版) | 大型改版 (架構變更, 不向下相容) | v1.x → v2.x (Windows → RHEL) |

→ 4 段為 patch, 3 段為主功能改版。
→ 主版號變 = 不向下相容 (例: 換 OS、換 DB 引擎、換認證模型)。

---

## 每個 Patch 的目錄結構

```
patches/v1.0.0.X/
├── PATCH_NOTE.md         # 此 patch 解什麼問題 + 影響檔案 + 套用 + 測試方式 (必要)
├── apply.ps1             # 一鍵套用此 patch 的腳本 (必要, 在 SF 主機跑)
└── files/                # 此 patch 的「修正後」檔案 (必要, 鏡像 SF 專案結構)
    ├── deploy/
    ├── scripts/
    └── ...
```

**files/** 的結構**必須鏡像 SF 專案根**, 例如:
- 主專案 `deploy/offline/install_offline.ps1`
- Patch 鏡像 `patches/v1.0.0.X/files/deploy/offline/install_offline.ps1`

→ apply.ps1 可以無腦遞迴拷貝 `files/*` 到 `<SF-PROJECT-ROOT>/*`。

---

## PATCH_NOTE.md 必填欄位

每個 patch 的 `PATCH_NOTE.md` 必填:

1. **Patch 編號 / 日期 / 適用版本**
2. **問題描述** (Symptom)
3. **根本原因** (Root cause)
4. **修正內容** (What changed)
5. **影響檔案** (Files modified / added)
6. **套用方式** (Apply, 含 idempotent 說明)
7. **測試方式** (Verification)
8. **相關 GitHub commit / issue 連結**

---

## apply.ps1 設計原則

1. **Idempotent**: 重跑無害
2. **Dry-run 支援**: 加 `-DryRun` 參數預演
3. **備份原檔**: 覆蓋前自動 `.bak`
4. **驗證**: 套用後跑簡單檢查
5. **退場**: 套用失敗有清楚 error message + 還原指引

---

## SF 主機 (內網) 怎麼拿到 patch

3 種方式 (擇一):

### 方式 A: GitHub Raw 直接下載 (有外網時)
```powershell
Invoke-WebRequest https://raw.githubusercontent.com/alienid4/cl_ftp/main/patches/v1.0.0.1/apply.ps1 -OutFile apply.ps1
```

### 方式 B: 帶 patch 進公司 (USB / Server)
1. 在外網 git clone 整個 repo
2. 把 `patches/v1.0.0.X/` 整個目錄拷到 USB / Server
3. 帶到 SF 主機解壓
4. 跑 `apply.ps1`

### 方式 C: 公司既有檔案 share
1. 把 patch 目錄丟到內網 share (例如 \\fileserver\IT\SF\patches\)
2. SF 主機從 share 拷 patch
3. 跑 apply.ps1

---

## 版本歷史

| Patch | 日期 | 摘要 | Commit |
|---|---|---|---|
| **v1.0.0** | 2026-05-19 | Initial release | 26e945c (tag 1.0) |
| **v1.0.0.1** | 2026-05-19 | 修 install_offline.ps1 找不到 installers 路徑問題 | 63b725c + e4a4bdf |
| **v1.0.0.3** | 2026-05-19 | install_offline.ps1 完全 idempotent + 容錯 + OpenSSH FoD 失敗指引 (跳號 v1.0.0.2 對應使用者指定) | 8628176 |
| **v1.0.0.4** | 2026-05-19 | OpenSSH 內網離線安裝 helper (用 Windows ISO sxs source) | 1054c1d |
| **v1.0.0.5** | 2026-05-19 | OpenSSH Portable 一鍵安裝 (Win32-OpenSSH zip, 5 MB, 不需 FoD/ISO) | 881e1ee |
| **v1.0.0.6** | 2026-05-19 | Patch 通用安裝器 (任意目錄可跑) + zip auto-find + fetch helper | 0eaca2e |
| **v1.0.0.7** | 2026-05-20 | Round 2 修正 (PS 5.1 相容 + portable OpenSSH 雙軌偵測 + 門檻調整 + health_check null/type) | 9b1674a |
| **v1.0.0.8** | 2026-05-20 | Round 3 修正 (sshd_config internal-sftp + 自動建 banner.txt) | d96d51e |
| **v1.0.0.9** | 2026-05-20 | Round 4 修正 (_portal 路徑統一 + 7 個 deploy 腳本 bug) | b738cb0 |
| **v1.0.0.10** | 2026-05-20 | Round 5 修正 (sshd_config DenyUsers + 04 BatchMode + 09 wheels 離線) | 3ef9db4 |
| **v1.x 結束** | 2026-05-20 | Windows Server 分支 maintenance, 之後改 RHEL | — |
| **v2.0.0** | 2026-05-20 | 平台大改版: Windows Server → RHEL 8/9 | d498a23 |
| **v2.0.0.1** | 2026-05-20 | 單帳號 PoC (u01t) + 非互動 + 對齊 u0X 主管圖 + 純 HTTP | b8d4a0f |
| **v2.0.0.2** ⭐ | 2026-05-20 | 離線安裝包 (RHEL build script + offline installer) | (待 commit) |

---

## 將來新 Patch 流程 (給維護者)

```powershell
# 1. 先在 main branch 修檔
# (改 install_offline.ps1 或其他)
git add <file>
git commit -m "fix: 描述"
git push

# 2. 拷一份到 patches/ 對應目錄
$ver = 'v1.0.0.X'
mkdir patches\$ver\files
# (依需求建子目錄, mirror SF 專案結構)
Copy-Item <modified-file> patches\$ver\files\<相同路徑>\

# 3. 寫 PATCH_NOTE.md
# 4. 寫 apply.ps1 (從前一個 patch 複製改)
# 5. 更新 patches/README.md 的「版本歷史」表

# 6. Commit 整個 patch
git add patches/$ver/
git commit -m "patch: $ver - 描述"
git push
```

---

## 不要做的事

- ❌ 直接修改舊 patch 目錄 (要新增 patch 才對, 舊的留歷史)
- ❌ 把 binary 放進 patches/files/ (zip / exe / msi / whl 都不該進 git)
- ❌ 跳號 (v1.0.0.1 → v1.0.0.3, 中間漏)
- ❌ apply.ps1 沒 dry-run / 備份機制
- ❌ patch 沒寫 PATCH_NOTE.md
