# Patch v2.1.0 — Satellite 部署模式 (跳過 bundle, 解掉 file conflict 連環坑)

| 欄位 | 內容 |
|---|---|
| **版本** | v2.1.0 (中型改版, 對齊鐵律 10/11) |
| **日期** | 2026-05-20 |
| **觸發** | 使用者反饋: 「我有 Satellite」 |
| **狀態** | ⭐ **強烈推薦, 取代 v2.0.0.X bundle 模式** |

---

## 為什麼版號跳到 v2.1.0 (不是 v2.0.0.11)

對應 SKILL 版本規則:
- `v2.0.0.X` = bug fix patch (小修)
- `v2.X.0` = **中型改版**, 新功能加入 (本次 ⭐)
- `v3.0.0` = 大型架構變動 (不向下相容)

Satellite 模式是**新的部署方式**, 不是 bug fix, 算 v2.1.0。
v2.0.x bundle 模式保留 (給沒 Satellite 的使用者)。

---

## 解了什麼根本問題

對應 SKILL 鐵律 10「Pull 模式優於 Push 打包」:

v2.0.0.6 ~ v2.0.0.10 (5 個 patch) 全在補 file conflict:
```
systemd → redhat-release → rocky-release → openssl-fips-provider → crypto-policies → ...
```

根因: **打包機 (Rocky 9.7) ≠ 主機 (RHEL 9.6)**, dnf download --alldeps 抓的 base packages 必跟主機已裝衝突。

v2.1.0 Satellite 模式: **主機從公司 Satellite pull 套件, Satellite 跟主機是同版 RHEL** → **0% file conflict**。

---

## 對照

| | v2.0.x Bundle 模式 (舊) | **v2.1.0 Satellite 模式 (新) ⭐** |
|---|---|---|
| 打包機 | GitHub Actions Rocky 9.7 | 不打包 |
| 主機怎拿套件 | USB tar.gz (141 MB) | Satellite (dnf install) |
| File conflict | 100% 撞 (要 EXCLUDE 5+ patch 補) | 0% (Satellite 是同版 RHEL) |
| 主機需要 | USB + 解壓 + 跑 install_offline.sh | 註冊 Satellite + dnf install |
| 套件數 | 311 個 (含 base) | ~30 個 (只裝需要的) |
| 升級 | 重打 bundle + 重抓 | `git pull` + `dnf upgrade` |
| 對齊公司流程 | ❌ 走私 | ✅ 標準 RHEL 維運 |

---

## 套用方式

### Step 1: 跟 IT / Satellite admin 拿 3 個值

```
SATELLITE_URL = https://satellite.<corp>.local
SATELLITE_ORG = <org-name>          # 例: Default_Organization
SATELLITE_KEY = <activation-key>    # 例: sf-server-key
```

(請 admin 給 SF 主機建一個 activation key, 訂閱 RHEL 9 BaseOS + AppStream)

### Step 2: SF 主機跑一行

```bash
sudo SATELLITE_URL=https://satellite.corp.local \
     SATELLITE_ORG=Default_Organization \
     SATELLITE_KEY=sf-server-key \
     SF_ACCOUNTS=u01t SF_PASSWORD='1qaz@WSX' \
     bash <(curl -fsSL https://github.com/alienid4/cl_ftp/raw/main/deploy-rhel/install_satellite.sh)
```

或先下載再跑:

```bash
sudo curl -fsSL https://github.com/alienid4/cl_ftp/raw/main/deploy-rhel/install_satellite.sh -o /tmp/install.sh
sudo SATELLITE_URL=... SATELLITE_ORG=... SATELLITE_KEY=... bash /tmp/install.sh
```

---

## 內部流程 (install_satellite.sh 做的事)

```
Step 0: 前置檢查 (RHEL 版本, 必填參數)
Step 1: 註冊 Satellite
   - 抓 katello-ca-consumer rpm
   - subscription-manager register --activationkey ...
Step 2: 確認 RHEL repo 可達 (dnf repolist)
Step 3: dnf install (從 Satellite 抓 ~30 個套件)
   - postgresql / nginx / samba / chrony / python / sssd / etc.
   - dnf 自己解 dependency, 沒 file conflict
Step 4: git clone SF repo
Step 5: 跑 deploy-rhel/install_all.sh (部署業務)
完成: 顯示訪問網址
```

---

## 升級方式 (將來 SF 更新)

```bash
cd /opt/sf
git pull           # 抓新 commit
sudo ./deploy-rhel/install_all.sh   # 重跑 (idempotent)

# RHEL 套件升級:
sudo dnf upgrade  # 從 Satellite 抓最新
```

不用打 patch, 不用重抓 bundle, 不用 EXCLUDE_PATTERN。

---

## 影響檔案

| 檔案 | 動作 |
|---|---|
| `deploy-rhel/install_satellite.sh` | **新增** (主 entry, 取代 install_offline.sh) |
| `deploy-rhel/install_offline.sh` | 保留 (給沒 Satellite 的人用) |
| 其他 `deploy-rhel/*.sh` | 不變 (install_all.sh 仍是核心) |

---

## v2.0.0.X bundle 模式何時還能用

| 情境 | 用什麼 |
|---|---|
| 公司有 Satellite | ⭐ v2.1.0 |
| 公司有內網 yum mirror (非 Satellite) | v2.1.0 改 SATELLITE_URL 指向 mirror |
| 公司有 RHEL 但完全 air-gap, 連 mirror 都沒 | v2.0.0.10 bundle (容忍 EXCLUDE 痛) |
| 個人 / PoC 環境 | v2.0.0.10 bundle 或 v2.1.0 |

---

## 對應 SKILL 鐵律

- **鐵律 10**: Pull 模式優於 Push 打包 ✓
- **鐵律 11**: 開工前評估公司既有基礎設施 ✓ (本次因使用者有 Satellite 才做)

---

## 相關連結

- 設計反思: [eval_20260520_1730_design_review.md](../../docs/runbook/eval_20260520_1730_design_review.md)
- 對應 runbook: [v2.1.0 Satellite 部署 SOP](../../docs/runbook/v2.1.0_20260520_satellite_deploy.md)
- 舊 bundle 模式: [v2.0.0.10 PATCH_NOTE](../v2.0.0.10/PATCH_NOTE.md) (保留)
