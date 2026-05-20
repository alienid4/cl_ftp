# Patch v2.0.0.7 — 過濾 base packages (解 redhat-release file conflict)

## 元資料 (對齊 SKILL 鐵律 3)

| 欄位 | 內容 |
|---|---|
| **Patch 編號** | v2.0.0.7 |
| **日期** | 2026-05-20 |
| **適用版本** | v2.0.0.5 / v2.0.0.6 後仍卡 redhat-release file conflict |
| **問題描述** | 套了 v2.0.0.6 (--skip-broken) 後跑 install_offline.sh, dnf 仍報:<br/>`file /usr/lib/systemd/system-preset/85-display-manager.preset from install of redhat-release-9.6-0.1.el9.x86_64 conflicts with file from package <已裝 redhat-release>` |
| **根本原因** | `--skip-broken` 只解 dependency 衝突, 不解 **file conflict**. Bundle 內的 redhat-release / systemd / kernel 等 base packages 跟 SF 主機已裝的同檔案路徑衝突. dnf 不知道該保留哪個 |
| **修正內容** | install_offline.sh 在 dnf install 前**過濾掉 base packages**:<br/>`EXCLUDE_PATTERN='redhat-release\|systemd-\|kernel-\|glibc-\|filesystem-\|setup-\|bash-\|libc-\|libgcc-\|libstdc'`<br/>`SAFE_RPMS=$(ls rpms/*.rpm \| grep -vE "/($EXCLUDE_PATTERN)")` |
| **影響檔案** | `install_offline.sh` (sf-bundle/ 內) |
| **套用方式** | 一行 curl-bash: `curl -fsSL https://github.com/alienid4/cl_ftp/raw/main/patches/v2.0.0.7/runpatch.sh \| sudo bash` |
| **測試方式** | `grep EXCLUDE_PATTERN sf-bundle/install_offline.sh` 應有結果<br/>跑後 dnf 不再卡 redhat-release file conflict, 開始裝 PostgreSQL / nginx / Samba 等 |
| **相關 commit** | (本次) |

---

## 結構

```
patches/v2.0.0.7/
├── PATCH_NOTE.md       ← 本檔
├── runpatch.sh         ← 工讀生一鍵套用 + 跑安裝
└── files/
    └── install_offline.sh  ← 修補版 (含 EXCLUDE_PATTERN)
```

---

## 過濾的 base packages 清單 (跟為什麼)

| Package pattern | 為什麼跳過 |
|---|---|
| `redhat-release*` | OS 版本標記檔, 主機已裝, 取代會破壞 OS 識別 |
| `systemd-*` | init 系統, protected, 替代會掛系統 |
| `kernel-*` | OS 核心, 絕對不要動 |
| `glibc-*` | C library, 全系統依賴, 替代會 boom |
| `filesystem-*` | FHS 根目錄定義, 主機已有 |
| `setup-*` | 基本系統設定, 已有 |
| `bash-*` | shell, 主機有 |
| `libc-*`, `libgcc-*`, `libstdc*` | 基礎 lib |

不影響: PostgreSQL / nginx / Samba / Python / chrony 等業務套件正常裝。

---

## 工讀生用 (一行)

```bash
curl -fsSL https://github.com/alienid4/cl_ftp/raw/main/patches/v2.0.0.7/runpatch.sh | sudo bash
```

或無外網時, USB 拷 runpatch.sh 到 SF 主機:
```bash
sudo bash runpatch.sh
```

預設帳號 `u01t` / 密碼 `1qaz@WSX`, 改:
```bash
sudo SF_ACCOUNTS=u02 SF_PASSWORD='xxx' bash runpatch.sh
```

---

## runpatch.sh 內部全自動

1. Auto-find sf-bundle/ (8 個常見位置)
2. 備份 install_offline.sh.bak.<timestamp>
3. 套 v2.0.0.7 install_offline.sh (有外網 curl, 無外網 inline 寫入)
4. 跑 install_offline.sh (帶帳號密碼環境變數)
5. 顯示訪問網址
