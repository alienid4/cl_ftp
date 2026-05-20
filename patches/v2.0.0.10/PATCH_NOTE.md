# Patch v2.0.0.10 — 加 openssl-fips-provider + crypto-policies 進 EXCLUDE

## 元資料

| 欄位 | 內容 |
|---|---|
| **Patch 編號** | v2.0.0.10 |
| **日期** | 2026-05-20 |
| **問題** | v2.0.0.9 過了 transaction check, 但 transaction test fail:<br/>`file /usr/lib64/ossl-modules/fips.so from install of openssl-fips-provider-1:3.5.1-7 conflicts with openssl-fips-provider-so-3.0.7-6.el9_5.x86_64` |
| **根因** | bundle 內 openssl-fips-provider 新版 (3.5.1) 跟主機已裝舊版 (3.0.7) 同檔 |
| **修正** | EXCLUDE_PATTERN 加 `openssl-fips-provider` 和 `crypto-policies` (兩者都是 OS 級 crypto 設定) |
| **影響檔** | install_offline.sh |
| **套用** | `curl -fsSL https://github.com/alienid4/cl_ftp/raw/main/release-zip/latest-runpatch.sh \| sudo bash` |

## 進度
| Patch | Filter 數 | 結果 |
|---|---|---|
| v2.0.0.6 | --skip-broken | 卡 file conflict |
| v2.0.0.7 | base packages (13) | 卡 rocky-release |
| v2.0.0.8 | + OS release (14) | 卡 openssl-fips |
| v2.0.0.9 | (同 .8 + 命名 fix) | 卡 openssl-fips |
| **v2.0.0.10** | **+ openssl-fips + crypto-policies (16)** | **應該過** |
