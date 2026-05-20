# Patch v2.0.0.4 — CI 修補 + Release asset 自動化

| 項目 | 值 |
|---|---|
| **版本** | v2.0.0.4 |
| **發布日期** | 2026-05-20 |
| **狀態** | ✅ CI fix + 第一個有 RPM bundle 的 release |

## 解了什麼

### CI fix (build script line 155)
v2.0.0.3 之前的 `build_offline_bundle.sh` 在 GitHub Actions 內失敗:
```
build_offline_bundle.sh: line 155: cd: deploy-rhel: No such file or directory
```

**根因**: 腳本內 `${BASH_SOURCE[0]}` 用 relative path 解析 dirname,
但 workflow 在 `cd "$OUTPUT_DIR/repo"` 後 cwd 不對。

**修法**: 在腳本最開頭 (cd 之前) 就把 `SCRIPT_DIR` / `LOCAL_REPO`
解成 absolute path。`git describe` 改用 `git -C $LOCAL_REPO ...`
(不依賴 cd)。

### Release asset 自動化
Push tag `v2.*` → workflow 自動跑 + 上傳 tar.gz 到對應 Release。

優於之前 Actions Artifact:
- 永久保留 (不是 30 天)
- 公開下載 (不用登入 GitHub)
- wget / curl 可直接抓
- 顯示在 Releases 頁

### 對應 issue (新增 docs/dev-log/issues_log.md)
- #024: GitHub Actions build_offline_bundle 失敗於 line 155

## 第一個 RPM bundle release

| 項目 | 值 |
|---|---|
| tar.gz | sf-bundle-YYYYMMDD_HHMM.tar.gz |
| 大小 | ~141 MB |
| 含 | 311 RPM (137 MB) + 31 Python wheels (12 MB) + repo source |
| RHEL 版本 | 9 (8 可重 trigger workflow 指定) |

## 套用方式

```bash
# 1. 下載 (公開 URL, 不用登入)
wget https://github.com/alienid4/cl_ftp/releases/download/v2.0.0.4/sf-bundle-XXXXX.tar.gz

# 2. 驗 hash
wget https://github.com/alienid4/cl_ftp/releases/download/v2.0.0.4/sf-bundle-XXXXX.tar.gz.sha256
sha256sum -c sf-bundle-*.sha256

# 3. SF 主機解壓 + 一鍵安裝
sudo mkdir -p /opt/install && cd /opt/install
sudo tar xzf sf-bundle-*.tar.gz
cd sf-bundle/
sudo SF_ACCOUNTS=u01t SF_PASSWORD='1qaz@WSX' ./install_offline.sh
```

詳見 runbook: [v2.0.0.3 windows pc build](../../docs/runbook/v2.0.0.3_20260520_1500_windows_pc_build.md)
(同邏輯, 只是這次不用自己跑 Docker, 直接 wget release asset)
