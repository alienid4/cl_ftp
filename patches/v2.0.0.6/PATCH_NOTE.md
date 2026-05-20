# Patch v2.0.0.6 — install_offline.sh 加 --skip-broken (修 systemd 衝突)

## 元資料 (對齊 SKILL 鐵律 3 — 8 大欄位)

| 欄位 | 內容 |
|---|---|
| **Patch 編號** | v2.0.0.6 |
| **日期** | 2026-05-20 |
| **適用版本** | v2.0.0 ~ v2.0.0.5 (使用者已下載 sf-bundle 但跑 install_offline.sh 卡 systemd 衝突) |
| **問題描述 (Symptom)** | `./install_offline.sh` 跑到 dnf 報錯:<br/>`Problem: The operation would result in removing the following protected packages: systemd, systemd-udev`<br/>建議 `--allowerasing` 或 `--skip-broken` |
| **根本原因 (Root cause)** | `dnf download --resolve --alldeps` 在打包機抓 RPM 時連同 systemd / glibc / kernel-tools 等 base packages 都被抓 (因為 PostgreSQL/Samba 等的 dependency)。SF 主機本來就有 systemd, dnf 想 replace 但 systemd 是 protected, replace 會掛系統 |
| **修正內容 (What changed)** | `install_offline.sh` 內 `dnf install` 指令加 `--skip-broken`:<br/>`dnf install -y --disablerepo='*' --skip-broken rpms/*.rpm` |
| **影響檔案 (Files modified)** | `install_offline.sh` (sf-bundle/ 內) |
| **套用方式 (Apply)** | sudo bash apply.sh (idempotent, 自動找 sf-bundle/, 備份原檔) |
| **測試方式 (Verification)** | `grep skip-broken sf-bundle/install_offline.sh` 應有結果 |
| **相關 commit** | 63d4db2 (build_offline_bundle.sh 上游修正), a375873 (release-zip patch) |

---

## 結構 (符合鐵律 3)

```
patches/v2.0.0.6/
├── PATCH_NOTE.md            ← 本檔 (8 大欄位)
├── apply.sh                 ← idempotent + dry-run + 備份
└── files/
    └── install_offline.sh   ← 修補後版本 (取代 sf-bundle/install_offline.sh)
```

---

## 套用方式 (4 種, 由簡到細)

### 🥇 路 1: apply.sh (對齊鐵律 3, 推薦)

```bash
# 1. 下載 patch 整套 (3 個檔)
cd /tmp
mkdir -p sf-patch-v2.0.0.6 && cd sf-patch-v2.0.0.6
mkdir -p files
wget https://github.com/alienid4/cl_ftp/raw/main/patches/v2.0.0.6/apply.sh
wget https://github.com/alienid4/cl_ftp/raw/main/patches/v2.0.0.6/files/install_offline.sh -O files/install_offline.sh
chmod +x apply.sh

# 2. 套用 (auto-find sf-bundle/)
sudo bash apply.sh

# 預演不動 (像 dry-run):
sudo bash apply.sh -DryRun

# 指定 sf-bundle 路徑:
sudo bash apply.sh -Target /opt/install/sf-bundle
```

### 🥈 路 2: 直接抓單檔覆蓋 (跳過 apply.sh)

```bash
cd sf-bundle/
sudo wget -O install_offline.sh \
  https://raw.githubusercontent.com/alienid4/cl_ftp/main/patches/v2.0.0.6/files/install_offline.sh
sudo chmod +x install_offline.sh
```

### 🥉 路 3: inline sed (不下載任何東西)

```bash
cd sf-bundle/
sudo sed -i "s|--disablerepo='\*'|--disablerepo='*' --skip-broken|" install_offline.sh
```

### 路 4: 跳過 install_offline.sh, 手動跑

```bash
cd sf-bundle/
sudo dnf install -y --disablerepo='*' --skip-broken rpms/*.rpm
sudo mkdir -p /opt/sf /opt/sf/python_wheels
sudo cp -r repo/* /opt/sf/
sudo cp wheels/* /opt/sf/python_wheels/
sudo chmod +x /opt/sf/deploy-rhel/*.sh
cd /opt/sf
sudo SF_ACCOUNTS=u01t SF_PASSWORD='1qaz@WSX' ./deploy-rhel/install_all.sh
```

---

## 為什麼不是「重抓 141 MB bundle」

| | |
|---|---|
| 變更檔案 | 1 個 (install_offline.sh) |
| 變更大小 | 1 行 (加 --skip-broken) |
| 應該 patch 大小 | < 5 KB |
| 全 bundle 大小 | 141 MB |

→ 對應 SKILL 鐵律 3「patch 給單獨可套用」原則, 不重灌。

---

## apply.sh 設計原則 (符合鐵律 3)

| 原則 | 實作 |
|---|---|
| **Idempotent** | 比對 SHA256, 已是最新就 skip exit 0 |
| **Dry-run** | `-DryRun` 預演只 echo, 不動檔 |
| **備份原檔** | 覆蓋前 cp 成 `*.bak.<timestamp>` |
| **自動偵測** | auto-find sf-bundle/ in `./sf-bundle`, `/opt/install/sf-bundle` 等 |
| **彩色輸出** | step / ok / warn / fail 對應 ANSI 顏色 |
| **友善 help** | `apply.sh -h` 顯示用法 |
| **退場明確** | fail 給明確 error, exit 1 |

---

## 相關連結

- 對應 SKILL 鐵律 3: [docs/dev-log/skill_sf_workflow.md](../../docs/dev-log/skill_sf_workflow.md)
- 上游修正: [v2.0.0.6 build_offline_bundle.sh](../../deploy-rhel/build_offline_bundle.sh) (給未來新打包的 bundle 用)
