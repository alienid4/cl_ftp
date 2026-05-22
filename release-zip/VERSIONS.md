# release-zip 版本對照

## 目錄結構 (USER 2026-05-22 強化)

```
release-zip/
├── VERSIONS.md                       (本檔)
├── latest-*.sh                       (當前最新版的別名, root)
├── 20260519/                         (該日的 versioned 檔)
├── 20260520/
├── 20260521/
└── 20260522/                         (今日)
```

### 命名規則
- `latest-<name>.sh` — root, 永遠指向當前最新版
- `<date>/<name>-v<major>.<minor>.<patch>.sh` — 版本化檔, 永遠不變內容

### 每次更新流程
```
1. deploy-rhel/<name>.sh 改完 bump version 字串
2. cp deploy-rhel/<name>.sh release-zip/<今天日期>/<name>-v<X.Y.Z>.sh
3. cp deploy-rhel/<name>.sh release-zip/latest-<name>.sh
4. 更新本 VERSIONS.md
```

---

## 當前 (latest = v2.3.7)

| 檔名 (versioned) | latest 別名 | 用途 |
|---|---|---|
| `20260522/install-portal-all-in-one-v2.3.7.sh` ⭐ | `latest-install-portal.sh` | 一次裝完整 Portal (含 nginx/postgresql/python/EPEL/wheel/source) |
| `20260522/sf-portal-source-v2.3.6.tar.gz` | - | Portal source code 打包 (14 KB) |
| `20260521/diagnose-v2.2.0.sh` | `latest-diagnose.sh` | 9 項診斷 |
| `20260521/net-check-v2.2.0.sh` | `latest-net-check.sh` | 測 SF 對外連通性 |
| `20260521/repo-check-v2.2.0.sh` | `latest-repo-check.sh` | 確認 dnf repo 來源 |

## 一次性 / 工具 (root)

| 檔名 | 用途 |
|---|---|
| `latest-install.sh` | install_online.sh (有 dnf mirror 環境用) |
| `latest-runpatch.sh` | 套 patches/ 目錄下的 patch |

---

## 版本歷史 (新 → 舊)

### v2.3.7 (2026-05-22) ⭐ 當前
- portal source 支援 tar.gz / zip 自動解壓 (新 Fallback 2)
- 加 sf-portal-source-v2.3.6.tar.gz 到 release-zip (14 KB)
- USER 不用 WinSCP 整個 portal/ 目錄, 1 個 tar 解決

### v2.3.6 (2026-05-22)
- portal source 用 `find /tmp /opt /root /home -name 'wsgi.py'` 動態找
- 加候選 /tmp/epel-rpms/portal /tmp/sf/portal 等

### v2.3.5 (2026-05-22)
- find_file maxdepth 2→5 (容納 RPMs 在更深子目錄)
- grep 改用 ERE `\([0-9]+\)\.` 精準過濾 "(N).rpm" 重複下載
- 失敗時自動 dump /tmp/ftp-lab/ 結構

### v2.3.4 (2026-05-22)
- 全套裝 (nginx + postgresql + initdb + 反代設定 + SELinux)
- 100% idempotent, snapshot 後一次裝完

### v2.3.3 (2026-05-22)
- 清掉舊 /opt/portal/app/ 再 cp (避免 patch 殘留)
- 拿掉 auto-patch wsgi.py (grep -E `\s` 在 ERE 不認, 改用 `[[:space:]]` 純驗證)

### v2.3.2 (2026-05-22)
- 整合 v2.2.0 → v2.3.1 所有 fix 成 all-in-one 一支 sh

### v2.2.6 (2026-05-22)
- 換成 install_portal_all_in_one 前的最後 fix-portal

### v2.2.5 (2026-05-21)
- 動態抓 gunicorn binary 路徑 (EPEL 21.2.0 是 /usr/bin/gunicorn 不是 gunicorn-3)

### v2.2.4 (2026-05-21)
- set -e 拿掉, DB/user 創建永遠跑 (不關 appsettings.json)

### v2.2.3 (2026-05-21)
- 修 PostgreSQL CREATE DATABASE 不能在 DO block

### v2.2.2 (2026-05-21)
- Step 1a 加裝 RHEL AppStream jinja2/packaging/pyasn1/six/setuptools
- 過濾重複下載 "(1).rpm"
- dnf install 加 --allowerasing

### v2.2.1 (2026-05-21)
- fix_portal.sh 支援散檔 *.rpm + 預打 tar + curl github 三種來源

### v2.2.0 (2026-05-21)
- 加 `/tmp/ftp-lab` 為主要 USER 軟體目錄
- release-zip 所有 sh 加版本號

### v2.1.0 (2026-05-20)
- Satellite 部署模式

### v2.0.0 (2026-05-20)
- RHEL 8/9 主架構, 取代 Windows Server
