# Patch v2.0.0.6 — install_offline.sh 加 --skip-broken (修 systemd 衝突)

| 項目 | 值 |
|---|---|
| **版本** | v2.0.0.6 |
| **發布日期** | 2026-05-20 |
| **狀態** | ✅ 必裝 (修 v2.0.0.5 bundle 在 SF 主機上的 dnf 衝突) |

## 解了什麼

使用者跑 `./install_offline.sh` 時出現:

```
Error:
Problem: The operation would result in removing the following
protected packages: systemd, systemd-udev
(try to add '--allowerasing' or '--skip-broken')
```

## 根因

`dnf download --resolve --alldeps` 在打包機抓 RPM 時,
連同 systemd / glibc / kernel-tools 等 base packages 都被抓下來
(因為它們是 PostgreSQL/Samba 等套件的 dependency)。

但 SF 主機**本來就有** systemd 等 base packages, 不需要也不能取代
(systemd 是 protected, replace 會讓系統掛掉)。

## 修法

`install_offline.sh` 內的 dnf install 加 `--skip-broken`:

```bash
dnf install -y --disablerepo='*' --skip-broken rpms/*.rpm
```

→ 衝突的 (systemd 等) skip, 其他 PostgreSQL / nginx / samba 等需要的還是裝。

## 使用者立即解 (不用等 v2.0.0.6 release)

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

## v2.0.0.6 release 預期

Tag 推完後 workflow 自動 build + 上傳:
https://github.com/alienid4/cl_ftp/releases/tag/v2.0.0.6
含 sf-rhel-bundle-*.tar.gz (~141 MB, 跟 v2.0.0.5 內容相同, 只是 install_offline.sh 加了 --skip-broken)。

