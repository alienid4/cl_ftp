# Patch v2.0.0.2 — 離線安裝包 (RHEL 無外網部署)

| 項目 | 值 |
|---|---|
| **版本** | v2.0.0.2 |
| **發布日期** | 2026-05-20 13:30 |
| **狀態** | ✅ 必裝 (SF 主機無外網時) |

---

## 使用者需求

> "相關軟體打包給我"

SF 主機通常**內網隔離**, 不能 `dnf install` 線上抓套件。要對應 Windows v1.x 的 `sf_offline_bundle` 概念, 把所有東西打包成 tarball, USB 拷進 SF 主機跑。

---

## 新增 2 個檔

### 1. `deploy-rhel/build_offline_bundle.sh`

**用途**: 在「外網 RHEL 8/9 PC」跑, 打包所有 SF 主機需要的東西成 tarball。

打包內容:
| 項目 | 來源 | 大小 |
|---|---|---|
| RPM 套件 | `dnf download --resolve --alldeps` | ~200 MB |
| Python wheels | `pip3 download` | ~20 MB |
| Repo source | `git clone --depth=1` | ~5 MB |
| install_offline.sh | 自動產生 | 2 KB |
| README.md | 自動產生 | 3 KB |
| **總計** | | **~225 MB tarball** |

包含的 RPM (對齊 deploy-rhel 各步驟):

| 類別 | 套件 |
|---|---|
| 基本 | git, curl, wget, tar, vim, bc, openssl |
| SSH | openssh, openssh-server, openssh-clients |
| DB | postgresql, postgresql-server, postgresql-contrib, python3-psycopg2 |
| Web | nginx, python3, python3-pip, python3-virtualenv |
| Samba | samba, samba-common, samba-client, cifs-utils |
| NTP | chrony |
| 監控 | sysstat, audit, mailx |
| AD | realmd, sssd, sssd-tools, adcli, samba-common-tools, krb5-workstation, oddjob, oddjob-mkhomedir, authselect |

包含的 Python wheels:
- flask, waitress, gunicorn
- psycopg2-binary
- python-ldap, ldap3
- requests, cryptography
- flask-login, flask-session
- pyjwt, werkzeug

### 2. `deploy-rhel/09_deploy_portal.sh` (改進)

**加離線 wheels 偵測** (對應 Windows v1.0.0.10 修法):

```bash
# 多路徑找 wheels (按順序試):
# 1. /opt/sf/python_wheels   (install_offline.sh 放這)
# 2. /opt/python_wheels
# 3. $REPO_ROOT/../wheels
# 4. $REPO_ROOT/wheels

if wheels 目錄存在; then
    pip install --no-index --find-links <wheels> -r requirements.txt
else
    pip install -r requirements.txt   # 走 pypi (需外網)
fi
```

→ 純離線環境用 wheels, 有外網仍可走 pypi。

---

## 流程 (外網 PC → SF 主機)

```
[外網 RHEL PC]                                      [SF 主機 (內網)]

1. git clone https://github.com/alienid4/cl_ftp
2. cd cl_ftp
3. sudo ./deploy-rhel/build_offline_bundle.sh
   ↓ 抓 200 MB RPM + 20 MB wheels + repo
   ↓ 打包 sf-rhel-bundle-YYYYMMDD.tar.gz (~225 MB)

4. USB 拷 tar.gz                ──USB──►   5. 解壓:
                                                tar xzf sf-rhel-bundle-*.tar.gz
                                                cd sf-rhel-bundle/

                                             6. 一鍵安裝:
                                                sudo SF_ACCOUNTS=u01t \
                                                     SF_PASSWORD='1qaz@WSX' \
                                                     ./install_offline.sh

                                             7. install_offline.sh 內部跑:
                                                a. dnf install --disablerepo='*' rpms/*.rpm
                                                b. cp -r repo/* /opt/sf/
                                                c. cp wheels/* /opt/sf/python_wheels/
                                                d. /opt/sf/deploy-rhel/install_all.sh

                                                完成, 顯示訪問網址
```

---

## 套用方式

### 在外網 PC

```bash
# 1. clone repo
git clone https://github.com/alienid4/cl_ftp /tmp/sf
cd /tmp/sf

# 2. 確認在最新版 (v2.0.0.2 含 build script)
git pull
git describe --tags

# 3. 打包 (預設輸出 /tmp/sf-rhel-bundle)
sudo ./deploy-rhel/build_offline_bundle.sh

# 4. tar.gz 在 /tmp/sf-rhel-bundle-YYYYMMDD_HHMM.tar.gz
ls -lah /tmp/sf-rhel-bundle-*.tar.gz
```

### 在 SF 主機

```bash
# 1. USB 接 SF 主機, 拷 tar.gz
# (略, 視 USB mount point 而定)

# 2. 解壓
mkdir -p /opt/install
cd /opt/install
tar xzf /mnt/usb/sf-rhel-bundle-YYYYMMDD_HHMM.tar.gz
cd sf-rhel-bundle/

# 3. 一鍵離線安裝
sudo SF_ACCOUNTS=u01t SF_PASSWORD='1qaz@WSX' ./install_offline.sh
```

---

## 驗證

```bash
# RPM 都裝了
rpm -q postgresql-server nginx samba python3 chrony

# Python wheels 用對了
sudo -u portal /opt/portal/venv/bin/pip list

# 服務跑起來
systemctl is-active sshd nginx postgresql sf-portal

# 跑健康速查
sudo /opt/sf/deploy-rhel/health_check.sh
```

---

## 為什麼不直接 commit RPM 進 repo

- RPM 大 (200 MB), 超 GitHub 單檔 100 MB 限制
- 違反鐵律 5: binary 不進 git
- RPM 跟 RHEL 版本綁定 (RHEL 8 vs 9 不通用)
- 每次 RHEL 出 patch 都要重打包, repo 會爆

→ 給 build script 讓使用者自己打包, repo 乾淨。

---

## 為什麼不放 GitHub Release

| 考量 | 結論 |
|---|---|
| 大小限制 | 單 asset 2 GB, 200 MB 沒問題 |
| Classifier 擋 binary 上傳 | ⚠️ 之前測試會擋 |
| 版本控管 | 每次新 patch 都要重發 release |
| 簽名 | Microsoft 官方 ISO/RPM 已簽, mirror 反而會破壞信任鏈 |

→ 使用者自己跑 build script 比較乾淨。

---

## 影響檔案

| 檔案 | 動作 |
|---|---|
| `deploy-rhel/build_offline_bundle.sh` | 新增 (給外網 PC 跑) |
| `deploy-rhel/09_deploy_portal.sh` | 修改 (加離線 wheels 偵測) |

---

## 相關連結

- 對應 Linux 概念: yum + pip 離線打包標準作法
- 對應 Windows 版: [v1.x build_offline_bundle.ps1](../../deploy/offline/build_offline_bundle.ps1)
- 部署 SOP: [v2.0.0.2_20260520_1330_offline_bundle.md](../../docs/runbook/v2.0.0.2_20260520_1330_offline_bundle.md)
