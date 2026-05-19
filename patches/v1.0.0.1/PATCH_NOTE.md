# Patch v1.0.0.1 — 修 install_offline.ps1 找不到 installers 路徑問題

| 項目 | 內容 |
|---|---|
| **Patch 編號** | v1.0.0.1 |
| **發布日期** | 2026-05-19 |
| **適用版本** | v1.0.0 (bundle `sf_offline_bundle_20260519_0901.zip`) |
| **嚴重程度** | 🔴 高 (擋住 install_offline.ps1 整個流程) |
| **相關 commit** | `63b725c`, `e4a4bdf` |
| **相關 Issue** | docs/known_issues.md #1 |

---

## 1. 問題描述 (Symptom)

在 SF 主機解壓 bundle 後跑 `install_offline.ps1`, 在 Step 0 前置檢查就失敗:

```
============================================================
 Step 00: 前置檢查
============================================================
[FAIL] 找不到 installers 目錄: ...\deploy\offline\installers
  確認 bundle 完整解壓
```

---

## 2. 根本原因 (Root cause)

兩個 fetch 腳本的目錄結構約定不一致:

| 腳本 | 抓 binary 到 |
|---|---|
| `build_offline_bundle.ps1` | `<bundle>/installers/`, `<bundle>/python_wheels/` |
| `fetch_binaries_win11.ps1` | `<bundle>/sf_binaries/installers/`, `<bundle>/sf_binaries/python_wheels/` |

而 `install_offline.ps1` 只認 **第一種**結構, 用 `fetch_binaries_win11.ps1` 抓的 bundle 它找不到。

---

## 3. 修正內容 (What changed)

### A. install_offline.ps1 自動偵測

新版會嘗試兩種路徑, 找到哪個用哪個:
```powershell
$installersDir = Join-Path $BundleDir 'installers'
if (-not (Test-Path $installersDir)) {
    $altInstallers = Join-Path $BundleDir 'sf_binaries\installers'
    if (Test-Path $altInstallers) { $installersDir = $altInstallers }
}
```

### B. 新增獨立 patch 腳本 patch_bundle_paths.ps1

對於不能 git pull 的 SF 主機, 跑 `patch_bundle_paths.ps1` 把 `sf_binaries/installers` Move 到 `<bundle>/installers`, 強制變回 install_offline.ps1 預期結構。

---

## 4. 影響檔案

| 檔案 | 動作 |
|---|---|
| `deploy/offline/install_offline.ps1` | **修改** (自動偵測邏輯) |
| `scripts/patch_bundle_paths.ps1` | **新增** |
| `docs/known_issues.md` | **新增** (記錄此問題 + workaround) |

---

## 5. 套用方式 (Apply)

### 方法 A: 用 apply.ps1 (推薦)

在 SF 主機, 把整個 `patches/v1.0.0.1/` 目錄 (含 files/ 子目錄) 拷到專案根, 然後:

```powershell
cd <SF-PROJECT-ROOT>
.\patches\v1.0.0.1\apply.ps1
```

### 方法 B: 跑 patch_bundle_paths.ps1 (僅修路徑, 不換 install_offline.ps1)

如果只想快速繞道 (不想換 install_offline.ps1), 跑這支:
```powershell
cd <SF-PROJECT-ROOT>\deploy\offline
.\..\..\scripts\patch_bundle_paths.ps1
```

### 方法 C: 純手動 (1 行解法)

```powershell
cd <SF-PROJECT-ROOT>\deploy\offline
Move-Item .\sf_binaries\installers .\installers
Move-Item .\sf_binaries\python_wheels .\python_wheels
```

---

## 6. 測試方式 (Verification)

套用後跑:
```powershell
cd <SF-PROJECT-ROOT>\deploy\offline
.\install_offline.ps1 -DryRun
```

預期看到 (摘要):
```
============================================================
 Step 00: 前置檢查
============================================================
[ok] 管理員權限
[ok] bundle 結構正常
     installers: ...\deploy\offline\installers
     wheels:     ...\deploy\offline\python_wheels
     deploy:     ...\deploy

============================================================
 Step 01: Visual C++ Redistributable 2015-2022
============================================================
[exec] Install VC++ Redistributable
       ...\vc_redist.x64.exe /install /quiet /norestart
       (dry-run)
... (繼續其他 step)
```

→ 看到 `[ok] bundle 結構正常` 即表示 patch 成功。

---

## 7. 退場 / 還原 (Rollback)

apply.ps1 會把原檔備份成 `.bak.<時間戳>`, 還原方式:
```powershell
# 例如還原 install_offline.ps1
$bakFile = Get-ChildItem deploy\offline\install_offline.ps1.bak.* | Select-Object -Last 1
Copy-Item $bakFile.FullName deploy\offline\install_offline.ps1 -Force
```

不過建議**不要還原** (這 patch 修的是 bug, 還原會踩回坑)。

---

## 8. 相關連結

- GitHub commits: [63b725c](https://github.com/alienid4/cl_ftp/commit/63b725c), [e4a4bdf](https://github.com/alienid4/cl_ftp/commit/e4a4bdf)
- 已知問題詳述: [docs/known_issues.md](../../docs/known_issues.md) #1
- 主 README: [../../README.md](../../README.md)
