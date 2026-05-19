# Dev-Log — 開發者紀錄

SF 專案的開發者紀錄目錄, **每次互動都要留紀錄**, 不靠記憶。

---

## 三大檔案

| 檔案 | 用途 | 何時寫 |
|---|---|---|
| [skill_sf_workflow.md](skill_sf_workflow.md) | **規範 / SKILL** — Claude 工作流程紀律 | 規範更新時 |
| [issues_log.md](issues_log.md) | **錯誤追蹤** — 每個錯誤一筆 | 每次新錯誤出現 |
| [dev_journal.md](dev_journal.md) | **時間軸日誌** — 每次重大進展 | 每次完成段落 |

---

## 規範摘要

> 詳見 [skill_sf_workflow.md](skill_sf_workflow.md) 的 8 大鐵律

1. 每個錯誤進 `issues_log.md` (#NNN 編號)
2. 每次重大進展寫 `dev_journal.md`
3. 每次檔案修改產生對應 `patches/vX.X.X.X/`
4. `.ps1` 一律 UTF-8 with BOM
5. binary 絕對不進 git
6. 真實主機 / 員工 / IP 全 placeholder
7. 大檔走 server / USB, 不放 GitHub Release
8. 每次互動結尾自我檢查

---

## 統計快查

```
Issues:   9 筆 (✅ 7 / 🟡 2 / 🔴 0 / 🆕 0)
Patches:  1 個 (v1.0.0.1)
Sessions: 3 天 (2026-05-17 ~ 2026-05-19)
Commits:  7 個
.ps1 BOM 覆蓋率: 100% (25/25)
```

---

## 將來接手的人讀這順序

1. `README.md` (主) — 5 分鐘
2. `docs/architecture-v2.html` — 10 分鐘 (視覺)
3. `docs/dev-log/skill_sf_workflow.md` — 5 分鐘 (規範)
4. `docs/dev-log/issues_log.md` — 知道踩過什麼坑
5. `docs/dev-log/dev_journal.md` — 知道為什麼這樣設計
6. `patches/README.md` — 修補規範
7. `docs/deployment_sop.md` — 部署 SOP

讀完約 30-45 分鐘可上手。
