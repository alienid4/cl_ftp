# Patch v2.0.0.9 — 檔名加版本 + latest-runpatch.sh

## 元資料

| 欄位 | 內容 |
|---|---|
| **Patch 編號** | v2.0.0.9 |
| **日期** | 2026-05-20 |
| **問題描述** | 使用者跑 v2.0.0.8 但仍卡 rocky-release 衝突<br/>→ 實際跑的是 v2.0.0.7 URL (沒換成 .8)<br/>「runpatch.sh 加版本號 我才不會搞錯」 |
| **根本原因** | 過去 runpatch.sh 都同名 (`runpatch.sh`), URL 只差版本目錄, 使用者複製貼時容易沒換 |
| **修正內容** | 1. 檔名直接帶版本: `runpatch_v2.0.0.9.sh`<br/>2. 加 `release-zip/latest-runpatch.sh` 永遠指向最新版<br/>3. 跑時印超大 banner 顯示版本 (避免誤跑舊版) |
| **影響檔案** | `patches/v2.0.0.9/runpatch_v2.0.0.9.sh`, `release-zip/latest-runpatch.sh` |
| **套用方式** | 一行 (見下方) |
| **測試方式** | 開頭 banner 應印 `RUNPATCH v2.0.0.9` |

---

## 給工讀生 — 兩種 URL (擇一)

### 🥇 URL A: 永遠最新版 (推薦, 不用每次換)

```bash
curl -fsSL https://github.com/alienid4/cl_ftp/raw/main/release-zip/latest-runpatch.sh | sudo bash
```

→ 永遠抓最新版 (v2.0.0.9 現在, 之後新版也是這 URL)

### 🥈 URL B: 鎖定特定版本 (要 reproducibility 時)

```bash
curl -fsSL https://github.com/alienid4/cl_ftp/raw/main/patches/v2.0.0.9/runpatch_v2.0.0.9.sh | sudo bash
```

→ 只跑 v2.0.0.9, 不會跟著新版動

---

## 跑時你會看到的 banner (一眼識別版本)

```
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║   SF File Exchange Server — RUNPATCH v2.0.0.9                ║
║   Date: 2026-05-20                                           ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝

  Features: 檔名帶版本 + Rocky vs RHEL release filter + base packages filter

  如果版本不是你預期的, 換 URL 用最新版:
    curl -fsSL https://github.com/alienid4/cl_ftp/raw/main/release-zip/latest-runpatch.sh | sudo bash
```

---

## 命名規範 (從這版起)

| 類型 | 命名 | 用途 |
|---|---|---|
| 特定版本 runpatch | `runpatch_v2.0.0.X.sh` | 鎖版 (在 patches/v2.0.0.X/) |
| 永遠最新版 | `latest-runpatch.sh` | release-zip/ 內, 每次推新版時更新 |

---

## 修了什麼 (跟之前 patch 的累積)

| Patch | 修了什麼 |
|---|---|
| v2.0.0.5 | (base release) |
| v2.0.0.6 | dnf --skip-broken |
| v2.0.0.7 | 過濾 base packages (systemd / kernel / glibc / 等) |
| v2.0.0.8 | 加 rocky-release 進 EXCLUDE |
| **v2.0.0.9** | **檔名帶版本 + latest-runpatch.sh + banner** |

v2.0.0.9 的 install_offline.sh 內容跟 v2.0.0.8 一樣 (含 rocky-release filter), 重點是 **runpatch 命名**。

---

## 結構

```
patches/v2.0.0.9/
├── PATCH_NOTE.md
├── runpatch_v2.0.0.9.sh           ← 檔名帶版本 (新規範)
└── files/
    └── install_offline.sh         ← v2.0.0.8 內容 (有 rocky-release)

release-zip/
└── latest-runpatch.sh             ← 永遠最新, 你只記這個 URL
```
