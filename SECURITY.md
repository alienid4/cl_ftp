# Security Policy

## 回報安全問題 / Reporting Security Issues

如果您在這個專案中發現安全漏洞 (security vulnerability), **請不要直接開 Public Issue**。

請改用以下方式回報:

### 方式 1: GitHub Security Advisory (推薦)

→ https://github.com/alienid4/cl_ftp/security/advisories/new

填寫漏洞描述 + 影響範圍 + 重現步驟。維護者會在 7 天內回覆。

### 方式 2: Email

私訊維護者: (請替換為您的聯絡方式, 例如 `security@example.com`)

請附上:
- 漏洞描述
- 受影響的檔案 / 版本
- 重現步驟
- 建議修補方式 (若有)

---

## 支援的版本 / Supported Versions

| 版本 | 安全更新支援 |
|---|---|
| v1.0.x | ✅ 主動支援 |
| v0.x.x (early) | ❌ 不支援 |

---

## 已知議題 / Known Considerations

本專案為 **reference implementation**, 部署到正式環境前**必須**考量:

1. **AD / LDAP 連線** — `.env` 中的 `AD_BIND_PASS` 屬於敏感資訊, 必須走公司 PAM 或 Key Vault 管理, 絕對不可進 git
2. **SQL Connection String** — 同上, 走環境變數或秘密管理
3. **SSL 憑證 (.pfx)** — 由公司 PKI 核發, 不進 git
4. **Service accounts (svc_portal / svc_pam)** — 最小權限原則, 走公司帳號管理流程
5. **Portal 的 `SECRET_KEY`** — 部署時必須改為隨機 32+ 字元
6. **Windows Firewall** — 來源 IP 必須走白名單, 不可開整網段
7. **PAM 揭露密碼** — 屬於高風險操作, 必須有完整稽核 trail

→ 詳見 [docs/deployment_sop.md](docs/deployment_sop.md) 與 [docs/required_packages.md](docs/required_packages.md)

---

## 回應時程 / Response Timeline

| 階段 | 時程 |
|---|---|
| 收到通報 → 初步確認 | 3 工作日內 |
| 確認漏洞 → 修補規劃 | 7 工作日內 |
| 修補完成 → 釋出 patch | 視嚴重程度, 高風險 30 天內 |
| Public Advisory | 修補後 + 90 天 (給使用者時間更新) |

---

## 致謝

感謝您協助本專案的安全。負責任的揭露者將於 release notes 致謝 (若您希望具名)。

---

## 不在範圍 / Out of Scope

下列不算 security issue:
- 開發者本機環境的設定錯誤
- 公開 demo 資料 (u01~u04 業務代號 / 假名 / RFC 1918 IP) 等示範值
- Markdown 排版問題
- 一般 bug (請開 Issue)
