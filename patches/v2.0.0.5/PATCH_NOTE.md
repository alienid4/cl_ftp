# Patch v2.0.0.5 — CI permissions fix (release upload)

| 項目 | 值 |
|---|---|
| **版本** | v2.0.0.5 |
| **發布日期** | 2026-05-20 |
| **狀態** | ✅ Tag for triggering release with RPM bundle |

## 解了什麼

v2.0.0.4 workflow run #4 build 成功 (3m 25s) 但 release upload fail:
```
Too many retries
```

**根因**: GitHub Actions GITHUB_TOKEN 預設沒 `contents: write` 權限,
無法 create release + upload asset。

**修法**: workflow 加 `permissions: contents: write`。

## 此 tag 目的

純粹觸發 workflow 重跑 (因 v2.0.0.4 tag 不能 force move)。

跑完後 release 會自動建在:
https://github.com/alienid4/cl_ftp/releases/tag/v2.0.0.5

含 sf-rhel9-bundle-*.tar.gz (~141 MB)。
