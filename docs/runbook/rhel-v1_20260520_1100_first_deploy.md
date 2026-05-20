# Runbook: RHEL 首次部署 SF File Exchange Server

| 項目 | 值 |
|---|---|
| **類型** | rhel-v1 (新架構) |
| **日期** | 2026-05-20 11:00 |
| **適用對象** | Linux 工程師, RHEL 8/9 環境 |
| **預期結果** | SF 主機完整部署, 可訪問 Portal + SFTP + (可選 SMB) |
| **預估耗時** | 約 1 小時 (含 AD join) |

---

## 前提條件

- [ ] RHEL 8 或 9 VM (建議 8 vCPU / 16 GB RAM / 100 GB /opt + 1 TB /data)
- [ ] root 或 sudo 權限
- [ ] 網路通 (公司 DNS, 可達 AD DC, 可達 dnf mirror 或內部 yum repo)
- [ ] 公司 IT 已同意改 RHEL (見 [eval_20260520_0900_rhel_alternative.md](eval_20260520_0900_rhel_alternative.md))
- [ ] 如要接 AD: AD admin 帳號可用 (例 Administrator)

---

## 步驟 (3 段)

### 段 1: clone repo + 跑一鍵部署 (核心)

```bash
# 在 RHEL 主機
sudo dnf install -y git
cd /opt
sudo git clone https://github.com/alienid4/cl_ftp sf
cd sf

# 跑一鍵 (預設先跳過 AD)
sudo ./deploy-rhel/install_all.sh
```

完成後直接顯示訪問網址。

### 段 2: 接 AD (如果有準備)

```bash
# 先確認 DNS 指向公司 DC
cat /etc/resolv.conf  # 應該看到 corp.local 或公司 DNS server

# 接 AD
sudo SF_SKIP_AD=0 SF_AD_DOMAIN=corp.local SF_AD_JOIN_USER=Administrator \
    ./deploy-rhel/07_join_ad.sh

# 驗證
realm list
id <some-ad-user>
ssh <ad-user>@$(hostname)
```

### 段 3: 建 SFTP 帳號 (有 AP 系統要接時)

```bash
# 互動模式 (你想 3 個密碼)
sudo SF_BATCH_MODE=0 ./deploy-rhel/04_create_sftp_accounts.sh

# 或非互動 (從 PAM 取密碼)
for d in HR FIN OPS; do
    useradd -g sftp_users -d /data/exchange/$d/inbound -s /sbin/nologin sftp_${d,,}
    echo "sftp_${d,,}:$(openssl rand -base64 32)" | chpasswd
done

# 驗證
getent passwd | grep sftp_
```

---

## 預期結果

跑完 `install_all.sh` 看到:

```
========== 安裝結束 — Summary ==========
Step                           Status Detail
------------------------------------------------------------
00_check_prereqs.sh            ok
01_setup_directories.sh        ok
02_setup_ownership.sh          ok
03_install_openssh.sh          ok
04_create_sftp_accounts.sh     ok     (BatchMode 跳過建帳號)
05_setup_firewall.sh           ok
06_install_nginx.sh            ok
07_join_ad.sh                  skip   SF_SKIP_AD=1
08_setup_postgresql.sh         ok
09_deploy_portal.sh            ok
10_setup_chrony.sh             ok
11_setup_samba.sh              ok
12_setup_logging.sh            ok
13_setup_backup.sh             ok
14_setup_monitoring.sh         ok

========== 服務狀態 ==========
sshd       Running
nginx      Running
postgresql Running
sf-portal  Running
smb        Running

========== Port 監聽 ==========
22, 80, 5000, 5432, 445, 139

========== 訪問網址 ==========
Portal HTTP    : http://10.92.198.16/         <- 可訪問
SFTP           : sftp <user>@10.92.198.16     <- 帳號未建
SMB            : smb://10.92.198.16/<share>   <- 配置 OK
```

---

## 驗證

```bash
# 1. 健康速查
sudo ./deploy-rhel/health_check.sh

# 2. 從別台 PC 訪問 Portal
curl http://10.92.198.16/

# 3. SFTP 連線測試 (帳號建立後)
sftp sftp_hr@10.92.198.16

# 4. DB 連線
psql -h localhost -U portal -d file_exchange_audit
\dt   # 看 table
SELECT COUNT(*) FROM audit_log;

# 5. 看 log
journalctl -u sf-portal -f
journalctl -u sshd -f
tail -f /var/log/sf-portal/stdout.log
```

---

## 故障排除

### Portal 沒回應

```bash
# 看 service 狀態
systemctl status sf-portal

# 看 log
journalctl -u sf-portal -n 100

# 重啟
systemctl restart sf-portal

# 直接跑 (debug 用)
cd /opt/portal/app
sudo -u portal /opt/portal/venv/bin/python wsgi.py
```

### sshd 啟動失敗

```bash
# 驗 config 語法
sshd -t -f /etc/ssh/sshd_config

# 看 log
journalctl -u sshd -n 50

# 還原備份
ls /etc/ssh/sshd_config.bak.*
cp /etc/ssh/sshd_config.bak.<最新> /etc/ssh/sshd_config
systemctl restart sshd
```

### DB 連不上

```bash
# 看 postgres 狀態
systemctl status postgresql

# 看誰能連
sudo -u postgres psql -c "\du"

# 改密碼
sudo -u postgres psql -c "ALTER USER portal WITH PASSWORD 'new_password';"

# 確認 pg_hba.conf 允許
cat /var/lib/pgsql/data/pg_hba.conf | grep portal
```

### AD 加入失敗

```bash
# 確認 DNS
host -t SRV _kerberos._tcp.corp.local

# 確認 NTP 同步 (Kerberos 時間敏感, 偏差 > 5 分鐘會 fail)
chronyc tracking

# 用 verbose 重試
realm join -v --user=Administrator corp.local
```

### nginx 反向代理 fail

```bash
# 看 nginx error log
tail -50 /var/log/nginx/sf-portal-error.log

# SELinux 阻擋?
ausearch -m AVC --start recent | grep -i nginx

# 開放 nginx network connect
setsebool -P httpd_can_network_connect 1
```

---

## 環境變數客製

跑 install_all.sh 前可改:

```bash
export SF_DATA_ROOT=/data/exchange          # 業務檔 (預設 /data/exchange)
export SF_PORTAL_ROOT=/opt/portal           # 系統檔 (預設 /opt/portal)
export SF_AD_DOMAIN=corp.local              # AD domain
export SF_AD_JOIN_USER=Administrator        # 加 domain 用的帳號
export SF_SKIP_AD=0                         # 0=接 AD, 1=跳過 (預設 1)
export SF_PORTAL_PORT=5000                  # Flask port (內部)
export SF_DB_NAME=file_exchange_audit
export SF_DB_USER=portal
export SF_DB_PASS=$(openssl rand -hex 16)   # 自動產生
export SF_CORP_NET=10.0.0.0/8               # 公司內網段
export SF_NTP_SERVERS="ntp1.corp.local ntp2.corp.local"
export SF_BACKUP_TARGET=/backup/sf
export SF_ALERT_MAIL=it-admin@corp.local
export SF_BATCH_MODE=1                      # 1=不互動建帳號, 0=互動

sudo -E ./deploy-rhel/install_all.sh
```

---

## 個別 step 重跑

每個 .sh 都 idempotent, 重跑無害:

```bash
sudo ./deploy-rhel/01_setup_directories.sh
sudo ./deploy-rhel/02_setup_ownership.sh
sudo ./deploy-rhel/03_install_openssh.sh
# etc.
```

---

## 對照 Windows 部署 (給有舊環境的人)

| 項目 | Windows | RHEL |
|---|---|---|
| 一鍵部署腳本 | `install_offline.ps1` | `install_all.sh` |
| 前置檢查 | `00_check_prereqs.ps1` | `00_check_prereqs.sh` |
| 建目錄 | `01_setup_directories.ps1` | `01_setup_directories.sh` |
| 權限 | `02_setup_ntfs_acl.ps1` | `02_setup_ownership.sh` (chown + setfacl) |
| OpenSSH | `03_install_openssh.ps1` | `03_install_openssh.sh` (RHEL 原生) |
| 帳號 | `04_create_sftp_accounts.ps1` | `04_create_sftp_accounts.sh` |
| 防火牆 | `05_setup_firewall.ps1` | `05_setup_firewall.sh` (firewalld) |
| Web 反向代理 | `06_install_iis.ps1` | `06_install_nginx.sh` |
| DB | `08_install_sqlexpress.ps1` | `08_setup_postgresql.sh` |
| Portal | `09_setup_portal.ps1` + NSSM | `09_deploy_portal.sh` + systemd |
| NTP | `10_setup_ntp.ps1` (W32Time) | `10_setup_chrony.sh` |
| SMB | (內建) | `11_setup_samba.sh` (Samba 4) |
| Log | `11_setup_firewall_log.ps1` | `12_setup_logging.sh` (auditd + rsyslog) |
| 備份 | `15_setup_backup.ps1` | `13_setup_backup.sh` (rsync + cron) |
| 監控 | `16_setup_monitoring.ps1` | `14_setup_monitoring.sh` (sar + cron) |
| AD 整合 | (加入網域 GUI) | `07_join_ad.sh` (realm + sssd) |

---

## 相關文件

- [Linux User Guide](../LINUX_USER_GUIDE.md) — Linux ↔ Windows 速查
- [RHEL 評估](eval_20260520_0900_rhel_alternative.md) — 決策過程
- [規畫](../../patches/README.md) — 整體架構

---

## 下次重做 SOP

新環境照這份跑就好。
有新版 (例 rhel-v2) 會放 `docs/runbook/rhel-v2_<日期>_<topic>.md`。
