# 開發者工作日誌 / Dev Journal

時間順序記錄每天 / 每次重大進展。
**規範**: 每次跟 Claude 完成一件事就追加一筆 (尤其是會影響將來接手的人的決策)。

> 不是 commit log (那個看 `git log`), 是「**為什麼**這樣做」與「**做完什麼**」的高層紀錄。

---

## 2026-05-19 (週二) — 上 GitHub + Patch 規範建立

### 上午
- 對齊使用者: 主管圖路線 vs Z 方案 (Z 方案 = 主管圖 + 3 大增值)
- 確認: 雙網段 (OA / PRD), SF 跨在中間
- 確認: 業務代號 u01~u04 走 PAM, 簽核 5 人 ANY, 批次滑動 30s
- 確認: AD + PAM 都有, 第一階段 SQL Express → 第二階段公司 DB
- 重寫 plan (含 18 部署腳本 + 雙階段 DB + 批次簽核)

### 下午
- 用 Win11 跑 `fetch_binaries_win11.ps1` 抓 binary (33​3 MB)
- 修編碼問題 (#001, #002), 全 25 個 .ps1 加 BOM
- 補 NSSM 後完成打包 zip (343 MB, SHA256 `FF8DC0...4995E0`)
- GitHub repo `alienid4/cl_ftp` 建立 (Public)
- 4 個 commits 推上去 (Initial + .gitignore + sanitize + SECURITY.md)
- Description + 8 個 Topics 設好
- 8 個 Security 開關啟用 (Dependabot / Secret scanning / Push protection 等)
- v1.0.0 Release 發布 (source code only, **沒附** 343 MB zip — classifier 擋, 改走 server 分發)

### 晚上
- 使用者開始 SF 主機部署, 跑 install_offline.ps1 報「找不到 installers」(#007)
- 緊急修 install_offline.ps1 加自動偵測 → commit `63b725c`
- 新增 patch_bundle_paths.ps1 + known_issues.md → commit `e4a4bdf`
- **建立 `patches/` 目錄 + 規範**, 第一個 patch v1.0.0.1 → commit `c79440d`
- 更新 README 加 patches 與 known_issues 連結 → commit `fa6e362`
- 確立規範: **每次更新都要對應 patch + issues_log 新增 + journal 追加**

---

## 2026-05-18 (週一) — 設計 & 打包

### 上午
- 使用者貼出主管的架構圖 (Windows Server 版)
- 對齊: 不要做超越主管的東西, 要「**承載**主管圖 + 加值**」
- 列出 13 大模組對照: 主管圖 vs 我的 plan
- 確認 3 大增值: OA USER 取檔 / 業務簽核 / Portal 集中視覺化

### 下午
- 重寫 plan (Z 方案完整版), 含批次簽核設計
- 8 支新部署腳本 (10 NTP / 11 FW log / 12 FTPS / 13 Defender / 14 Quota / 15 Backup / 16 Monitoring / 17 弱掃指引)
- mockup-user.html 改批次列表 + 我的可下載 ZIP
- architecture-v2.html (Z 方案完整版)
- debug bundle 三件套 (collect / sanitize / health_check)
- AI Runtime Roadmap plan (與 SF 分離備忘)

### 晚上
- 寫離線安裝架構: build_offline_bundle.ps1, install_offline.ps1, fetch_binaries_win11.ps1
- USB 分發 SOP
- migrate_db_to_corp.ps1 (第二階段遷移)
- Portal Flask 骨架 (auth / db / blueprints / templates)

---

## 2026-05-17 (週日) — 對齊基本概念

- 使用者第一次描述系統: SFTP 上傳 SF, 通知簽核, samba 下載
- 釐清: u01 是業務代號 (非個人), 5 人 ANY 制簽核, 7 天保留
- 釐清: AD + PAM 有, SIEM 暫時無 (預留接)
- 釐清: 部門共用 SFTP 帳號 + 個人 AD 帳號 Portal/SMB 雙軌
- mockup 第一版 (cathay.css 風格)

---

## 將來新進展的記錄模板

```markdown
## YYYY-MM-DD (週X) — [簡短主題]

### 上午 / 下午 / 晚上
- 完成什麼 (簡短列點, 不寫程式碼)
- 重大決策 (為什麼這樣做)
- 卡關 (進不去的地方)
- 解法 (對應 issues_log 編號)

### 對應紀錄
- 新增 patch: vX.X.X.X
- 新增 issue: #NNN
- 主要 commit: <hash> <one-liner>
```

---

## 統計

```
Sessions: 3 天 (2026-05-17 ~ 2026-05-19)
Commits:  7 個 (alienid4/cl_ftp)
Patches:  1 個 (v1.0.0.1)
Issues:   9 筆 (7 已解 / 2 緩解)
```
