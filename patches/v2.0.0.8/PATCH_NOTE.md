# Patch v2.0.0.8 — 加 rocky-release 進 EXCLUDE (解 RHEL vs Rocky file conflict)

## 元資料

| 欄位 | 內容 |
|---|---|
| **Patch 編號** | v2.0.0.8 |
| **日期** | 2026-05-20 |
| **適用版本** | v2.0.0.7 過濾 base packages 後仍卡 rocky-release file conflict |
| **問題描述** | v2.0.0.7 過濾掉 13 個 base packages, 但跑 install 仍報:<br/>`file /etc/system-release from install of rocky-release-9.7-1.7.el9.noarch conflicts with file from package redhat-release-9.6-0.1.el9.x86_64`<br/>類似錯誤多筆: /etc/os-release, /etc/system-release-cpe, /usr/lib/os-release, /usr/lib/systemd/system-preset/* |
| **根本原因** | **bundle 是用 Rocky Linux 9.7 container 打包**, 內含 `rocky-release-9.7.rpm`<br/>SF 主機是 **RHEL 9.6**, 已裝 `redhat-release-9.6.rpm`<br/>兩個 RPM 都 own `/etc/system-release`, `/etc/os-release` 等同檔, dnf 不知道該保留哪個 |
| **修正內容** | EXCLUDE_PATTERN 加 `rocky-release` 及其他 RHEL clones:<br/>`'rocky-release\|redhat-release\|centos-release\|almalinux-release\|oraclelinux-release\|fedora-release\|systemd-\|...'` |
| **影響檔案** | `install_offline.sh` (sf-bundle/ 內) |
| **套用方式** | `curl -fsSL https://github.com/alienid4/cl_ftp/raw/main/patches/v2.0.0.8/runpatch.sh \| sudo bash` |
| **測試方式** | `grep 'rocky-release' install_offline.sh` 應有結果<br/>跑後 dnf 不再卡 rocky/redhat release 衝突 |

---

## 教訓: 為什麼會用 Rocky 9.7 打包 RHEL 9.6 bundle

GitHub Actions workflow 用 `rockylinux:9` Docker image (Rocky Linux 9 是 RHEL 9 的免費 clone)。

正常情況: Rocky 9 RPM 跟 RHEL 9 RPM 100% 通用 (binary 相同), **除了** OS 識別檔 (rocky-release vs redhat-release)。

`dnf download` 連 rocky-release 也抓進來, 但這個 RPM 不該裝到 RHEL 主機。

**v2.0.0.8 把它過濾掉**, 其他 RPM (PostgreSQL / nginx / Samba 等) 一樣通用, 不影響。

---

## 進度對照

| Patch | 修了什麼 | 結果 |
|---|---|---|
| v2.0.0.5 | (原 release) | 卡 systemd 衝突 |
| v2.0.0.6 | dnf --skip-broken | 還卡 redhat-release file conflict |
| v2.0.0.7 | 過濾 base packages | 還卡 rocky-release vs redhat-release |
| **v2.0.0.8** | **加 rocky-release 進 EXCLUDE** | **應該過了** |

---

## 預期過濾數

| 類別 | 過濾數 |
|---|---|
| v2.0.0.7 (base only) | 13 個 |
| **v2.0.0.8 (加 rocky-release 等)** | **~14-15 個** |

實際安裝 ~296-297 個 RPM (PostgreSQL / nginx / Samba / chrony / Python 等)。

---

## 結構

```
patches/v2.0.0.8/
├── PATCH_NOTE.md
├── runpatch.sh                 ← 工讀生一鍵
└── files/
    └── install_offline.sh      ← EXCLUDE 加 rocky-release
```

---

## 工讀生一行

```bash
curl -fsSL https://github.com/alienid4/cl_ftp/raw/main/patches/v2.0.0.8/runpatch.sh | sudo bash
```
