# release-zip 版本對照

## 當前 (latest = v2.2.1)

| 檔名 (versioned) | latest 別名 | 用途 |
|---|---|---|
| `fix-portal-v2.2.1.sh` ⭐ | `latest-fix-portal.sh` | 重建 Portal (支援散檔 .rpm + tar) |
| `diagnose-v2.2.0.sh` | `latest-diagnose.sh` | 9 項診斷 (sshd/nginx/portal/...) |
| `net-check-v2.2.0.sh` | `latest-net-check.sh` | 測 SF 對外連通性 |
| `repo-check-v2.2.0.sh` | `latest-repo-check.sh` | 確認 dnf repo + python3-flask 來源 |

## 一次性 / 工具

| 檔名 | 用途 |
|---|---|
| `latest-install.sh` | install_online.sh (有 dnf mirror 環境用) |
| `latest-runpatch.sh` | 套 patches/ 目錄下的 patch |
| `v2.0.0.6-install_offline.sh` | 早期離線 bundle 安裝 (已被 EPEL tar 取代) |

## EPEL Python Bundle

| 檔名 | 大小 | 內容 |
|---|---|---|
| `sf-epel-pyrpms.tar.gz` | ~1.7 MB | flask + werkzeug + gunicorn + 4 個依賴 |
| `sf-epel-pyrpms.tar.gz.sha256` | ~100 B | 上面的 SHA-256 |

(由 PC 手動下載 7 個 RPM + `pack_local_rpms.ps1` 產出; 詳見 `docs/runbook/v2.2.0_20260521_epel_pyrpms_manual.md`)

## 命名規則

- `<name>-v<major>.<minor>.<patch>.sh` — 版本化檔, 永遠不變內容
- `latest-<name>.sh` — 當前最新版的別名 (內容跟最新 versioned 同)

每次 patch 跟著:
1. `deploy-rhel/<name>.sh` 改完 bump version 字串
2. `cp deploy-rhel/<name>.sh release-zip/<name>-v<X.Y.Z>.sh`
3. `cp deploy-rhel/<name>.sh release-zip/latest-<name>.sh`
4. 更新本 VERSIONS.md

## 版本歷史

### v2.2.1 (2026-05-21)
- fix_portal.sh 支援 3 模式找 EPEL Python:
  1. 散檔 *.rpm (USER 直接 scp 7 個 RPM 到 /tmp/ftp-lab) ⭐
  2. 預打 tar (PC 跑 pack_local_rpms.ps1)
  3. curl github (有外網 fallback)

### v2.2.0 (2026-05-21)
- 加 `/tmp/ftp-lab` 為主要 USER 軟體目錄
- 加版本號於 release-zip 全部 sh 檔
- fix_portal.sh 支援 Portal source 從 /tmp/ftp-lab/portal 讀
- EPEL tar 候選位置從 /opt/sf 改為 /tmp/ftp-lab 優先

### v2.1.0 (2026-05-20)
- Satellite 部署模式 (`install_satellite.sh`)

### v2.0.0 (2026-05-20)
- RHEL 8/9 主架構, 取代 Windows Server
