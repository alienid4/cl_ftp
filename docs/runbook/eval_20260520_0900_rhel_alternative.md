# 評估: 改用 RHEL 取代 Windows Server 2022

| 項目 | 值 |
|---|---|
| **類型** | 架構評估 (非 patch) |
| **日期** | 2026-05-20 09:00 |
| **動機** | 使用者背景: Linux, 不熟 Windows; 改 RHEL 維護更輕鬆 |
| **結論** | ✅ 推薦改 RHEL (PoC + 正式都可行) |

---

## TL;DR

| 問題 | 答 |
|---|---|
| RHEL 可以取代 Windows 嗎? | ✅ 可以, 主管圖規畫的所有功能都能做 |
| AD 怎麼接? | `realm join corp.local` 一行加入 + sssd 自動配 |
| 規畫要重寫嗎? | ❌ 不用, 規畫 (帳號模型 / 簽核流程 / 目錄結構) 不變 |
| Portal 程式碼要重寫嗎? | ❌ 不用, Flask + waitress 跨平台 |
| SQL Server 怎辦? | 第一階段改用 PostgreSQL (Linux 原生); 第二階段公司 MSSQL 用 pyodbc + FreeTDS |
| 時程影響? | -3 天 (你熟, 比 Windows 學習快) |

---

## Windows Server vs RHEL 對照表

### 服務層

| 角色 | Windows Server 2022 | RHEL 8/9 | 評論 |
|---|---|---|---|
| **SFTP** | OpenSSH for Windows (我們用 portable) | OpenSSH 原生 (yum 一行裝) | RHEL 完勝 |
| **Web Portal 前端** | IIS + URL Rewrite + ARR | nginx + uwsgi | RHEL 配置簡單 |
| **Portal 後端** | Python Flask + waitress | Python Flask + gunicorn / uwsgi | 平手 (跨平台) |
| **本機 DB** | SQL Server 2022 Express | PostgreSQL 16 | 平手 (功能對等) |
| **公司 DB** | SQL Server | SQL Server (透過 pyodbc + FreeTDS) | 平手 |
| **SMB Share** | Windows SMB Server | Samba 4 | RHEL 略複雜但成熟 |
| **AD 認證** | 加入 AD domain (一鍵) | `realm join` (一行) | 平手 |
| **PAM 整合** | 公司 PAM 系統 (REST API) | Linux PAM (原生!) | RHEL 更原生 |
| **FTPS 備案** | IIS FTP Server | vsftpd + TLS | RHEL 簡單 |
| **防火牆** | Windows Firewall | firewalld / iptables | 你熟 firewalld |
| **排程** | Task Scheduler | cron / systemd timer | 你熟 cron |
| **NTP** | W32Time | chrony | RHEL 完勝 |
| **監控** | PerfMon + Defender | sar + collectd / Prometheus + Grafana | RHEL 完勝 |
| **EDR** | Windows Defender | ClamAV / CrowdStrike Falcon | 平手 |
| **備份** | Windows Server Backup | rsync / borgbackup / restic | 你熟 |
| **Log 集中** | Event Log → rsyslog forwarder | rsyslog / journald | RHEL 完勝 |

### 工具層

| 你 Linux 會的 | Windows 等價 | RHEL 等價 |
|---|---|---|
| `systemctl` | `Get-Service` | `systemctl` ✓ |
| `journalctl` | `Get-WinEvent` | `journalctl` ✓ |
| `vi /etc/...` | `notepad C:\ProgramData\...` | `vi /etc/...` ✓ |
| `iptables` | `Get-NetFirewallRule` | `firewalld` ✓ |
| `useradd` | `New-LocalUser` | `useradd` ✓ |
| `cron` | `Get-ScheduledTask` | `cron` ✓ |
| `df -h` | `Get-PSDrive` | `df -h` ✓ |
| `ps aux` | `Get-Process` | `ps aux` ✓ |
| `bash` | `PowerShell` | `bash` ✓ |

**全部你熟**。

---

## 主管圖功能對照 (規畫不變)

主管原圖內所有元素 RHEL 都能對應, 規畫零修改:

| 主管圖 | RHEL 實作 |
|---|---|
| 業務代號 u01~u0N | 同名 Linux user (本機 `/etc/passwd`) |
| Portal 簽核流程 (5 人 ANY 制) | Flask + SQL DB (Postgres or MSSQL) |
| AD 群組自助維護 | python-ldap 改 AD 群組 (跟 Windows 一樣) |
| SMB 部門下載區 | Samba 4 + AD 群組 ACL |
| 業務簽核控管 | 同 Portal 邏輯 |
| 集中視覺化 | 同 Portal 邏輯 |
| 7 天清理 + 365 天 AuditLog | cron + DB |
| 5 分鐘安全閥 (批次聚合) | 同 Portal 排程 (cron) |
| 防火牆白名單 | firewalld 或 nftables |
| TLS 1.2+ 強加密 | nginx ssl_protocols TLSv1.2 TLSv1.3 |
| NTP 同步 | chrony |
| PerfMon 監控 | sar + Prometheus |

---

## AD 接法 — RHEL 4 個 layer

### Layer 1: Kerberos (票證認證底層)

```bash
# /etc/krb5.conf
[libdefaults]
  default_realm = CORP.LOCAL
  dns_lookup_realm = false
  dns_lookup_kdc = true

[realms]
  CORP.LOCAL = {
    kdc = corp-dc1.corp.local
    kdc = corp-dc2.corp.local
    admin_server = corp-dc1.corp.local
  }

[domain_realm]
  .corp.local = CORP.LOCAL
  corp.local = CORP.LOCAL
```

測試:
```bash
kinit Administrator@CORP.LOCAL
klist   # 看票證
```

### Layer 2: realm + sssd (加入 domain, 一行)

```bash
# 安裝套件
sudo dnf install -y realmd sssd sssd-tools oddjob oddjob-mkhomedir \
                    adcli samba-common-tools krb5-workstation

# 加入 domain (跟 Windows "加入網域" 等價)
sudo realm join --user=Administrator corp.local

# 驗證
realm list
# 應該看到:
# corp.local
#   type: kerberos
#   realm-name: CORP.LOCAL
#   domain-name: corp.local
#   configured: kerberos-member
```

加入完成後, AD 帳號可直接登入 SF 主機:
```bash
ssh wang.manager@sf-host.corp.local
# 用 AD 密碼登入, 自動建 /home/wang.manager
```

### Layer 3: sssd 設定 (細節調整)

```ini
# /etc/sssd/sssd.conf (realm join 自動配, 通常不用改)
[domain/corp.local]
  default_shell = /bin/bash
  use_fully_qualified_names = False    # 用 user 不用 user@corp.local
  fallback_homedir = /home/%u
  ad_domain = corp.local
  krb5_realm = CORP.LOCAL
  realmd_tags = manages-system joined-with-adcli
  id_provider = ad
  access_provider = simple             # 限制誰能 ssh login

  # 只允許 sftp_users 群組 + IT 群組
  simple_allow_groups = sftp_users, dept_it_admins, dept_archi_view
```

restart:
```bash
sudo systemctl restart sssd
```

### Layer 4: PAM (auth flow)

`realm join` 自動配 `/etc/pam.d/`, 通常不用碰。如果要客製:

```bash
# /etc/pam.d/sshd 已自動包含:
auth       sufficient   pam_sss.so use_first_pass
account    sufficient   pam_sss.so
password   sufficient   pam_sss.so
session    optional     pam_mkhomedir.so   # 第一次登入自動建家目錄
```

---

## Portal 認證 AD (Flask 程式)

跟 Windows 版本**幾乎一樣**, 只是換 library:

```python
# Windows 用 win32security 或直接 IIS Windows Auth
# Linux 用 python-ldap 或 ldap3

from ldap3 import Server, Connection, ALL, NTLM
from flask_login import UserMixin

def authenticate_user(username, password):
    server = Server('corp-dc1.corp.local',
                    port=636,
                    use_ssl=True,
                    get_info=ALL)
    try:
        conn = Connection(server,
                          user=f'CORP\\{username}',
                          password=password,
                          authentication=NTLM,
                          auto_bind=True)
        # 查使用者群組
        conn.search('DC=corp,DC=local',
                    f'(sAMAccountName={username})',
                    attributes=['memberOf', 'mail', 'displayName'])
        if conn.entries:
            user_dn = conn.entries[0].entry_dn
            groups = [g.split(',')[0].replace('CN=','')
                      for g in conn.entries[0].memberOf]
            return {
                'username': username,
                'dn': user_dn,
                'groups': groups,
                'mail': str(conn.entries[0].mail),
                'displayName': str(conn.entries[0].displayName),
            }
    except Exception as e:
        return None
```

### 或用 Kerberos SSO (使用者瀏覽器走 Negotiate, 不輸密碼)

```nginx
# /etc/nginx/conf.d/sf-portal.conf
server {
    listen 443 ssl;
    server_name sf.corp.local;

    ssl_certificate /etc/pki/tls/certs/sf.crt;
    ssl_certificate_key /etc/pki/tls/private/sf.key;

    # Kerberos SSO (mod_auth_gssapi)
    location / {
        auth_gss on;
        auth_gss_realm CORP.LOCAL;
        auth_gss_keytab /etc/krb5.keytab;
        auth_gss_service_name HTTP/sf.corp.local;
        auth_gss_authorized_principal_regex .*@CORP.LOCAL;

        proxy_pass http://127.0.0.1:5000;
        proxy_set_header X-Remote-User $remote_user;   # Flask 從這 header 拿 AD 帳號
    }
}
```

Flask 拿 header:
```python
@app.before_request
def get_ad_user():
    ad_user = request.headers.get('X-Remote-User')   # wang.manager@CORP.LOCAL
    g.current_user = ad_user.split('@')[0] if ad_user else None
```

---

## SMB Share 接 AD (Samba 4)

```ini
# /etc/samba/smb.conf
[global]
  workgroup = CORP
  realm = CORP.LOCAL
  security = ads
  kerberos method = system keytab
  template homedir = /home/%U
  template shell = /bin/bash
  winbind use default domain = yes
  winbind offline logon = false

  log file = /var/log/samba/log.%m
  max log size = 50

  # 啟用 SACL audit (對齊主管圖稽核要求)
  full_audit:prefix = %u|%I|%S
  full_audit:success = connect disconnect open close write unlink rename
  full_audit:failure = connect open
  full_audit:facility = local5
  full_audit:priority = NOTICE

[architecture]
  path = /data/exchange/samba/architecture
  valid users = @"CORP\dept_archi_view", @"CORP\dept_it_admins"
  read only = no
  vfs objects = full_audit
```

加入 AD + 啟動:
```bash
sudo systemctl enable --now smb winbind
sudo net ads join -U Administrator
```

OA USER 從 Windows 訪問:
```
\\sf-host.corp.local\architecture
```

---

## 整體部署 outline (給你估時程)

| Phase | 工作 | 時間 |
|---|---|---|
| 0 | 跟公司確認: 允許 RHEL? VM 規格? | 1 天 |
| 1 | 申請 RHEL 8/9 VM + 加入 AD | 1 天 |
| 2 | 裝 OpenSSH + 設業務代號帳號 u01~u04 | 半天 |
| 3 | 裝 PostgreSQL + 跑 schema | 半天 |
| 4 | 設 Samba + AD 群組整合 | 1 天 |
| 5 | 部署 Flask Portal + nginx | 1 天 |
| 6 | 跑簽核流程煙霧測試 | 半天 |
| 7 | 跟公司 IT 串 NTP / Log forward / 監控 | 1 天 |
| 8 | 跑滲透測試 + 修 | 1 天 |
| **總計** | | **6-7 天** |

對照 Windows: 我們已花 2 天還沒讓 Portal 跑起來... RHEL 你應該 1 天就能讓 Portal 起來。

---

## 阻礙與替代方案

### 阻礙 1: 公司規定一定要 Windows

**替代**: 跟主管解釋 RHEL 同樣達到主管圖所有功能, 而且符合金融業稽核 (CIS Benchmark + STIG 規範完整)。

如果**還是不行**, 維持 Windows, 用我寫的 patch 慢慢推, 但你會更累。

### 阻礙 2: 公司 DB 是 MSSQL, RHEL 連不到?

**Linux 連 MSSQL 用**: `pyodbc` + `msodbcsql18` (Microsoft 官方 Linux ODBC driver, dnf 可裝)

```bash
sudo curl -o /etc/yum.repos.d/mssql-release.repo https://packages.microsoft.com/config/rhel/9/prod.repo
sudo dnf install -y msodbcsql18 mssql-tools18

python -c "import pyodbc; print(pyodbc.drivers())"
# 應該看到 'ODBC Driver 18 for SQL Server'
```

Flask 連 MSSQL:
```python
import pyodbc
conn = pyodbc.connect(
    'DRIVER={ODBC Driver 18 for SQL Server};'
    'SERVER=corp-sql01.corp.local,1433;'
    'DATABASE=FileExchangeAudit;'
    'Trusted_Connection=yes;'                # Kerberos SSO 走 AD
    'TrustServerCertificate=yes'
)
```

### 阻礙 3: 公司 PAM 系統只接 Windows agent?

**確認**: PAM 系統 (例如 CyberArk) 通常有 Linux agent。

如果**真沒 Linux 支援**, 可以折衷:
- Linux SF 主機保留, 但 u01~u0N 密碼仍由 PAM 揭露
- PAM 變成「外部密碼提供者」, 不直接管 Linux 帳號
- Linux 用 sudo / ssh-key 取代密碼登入

---

## 決策建議

### 強烈推薦改 RHEL 的場景
- ✅ 你 Linux 背景, 速度快 10 倍
- ✅ 公司允許 RHEL
- ✅ PoC 階段, 還沒大量部署
- ✅ 預算 RHEL 訂閱 / 公司有現成 VM

### 維持 Windows 的場景
- 公司明確規定金融業稽核 OS 限 Windows
- 已部署其他 Windows 系統, 一致性考量
- 維運團隊只有 Windows 經驗 (但你會接手, 不衝突)

### 我的建議

**問你的主管 + IT 一個問題**:
> 「PoC 可以用 RHEL 嗎? 因為我 Linux 背景, RHEL 開發速度快, 功能跟 Windows 版本完全等價。」

如果 OK → 馬上改, 我幫你寫 RHEL 部署 SOP。
如果不 OK → 繼續 Windows, 我繼續修 patch。

---

## 下一步 (兩個方向擇一)

### 方向 A: 改 RHEL (推薦)

```bash
# 1. 申請 RHEL 8/9 VM
# 2. 跟我說後, 我寫對應 RHEL 部署腳本
# 3. 大概 1 個禮拜可以跑起來
```

我會建立:
- `deploy-rhel/01_install_packages.sh`
- `deploy-rhel/02_setup_directories.sh`
- `deploy-rhel/03_join_ad.sh`
- `deploy-rhel/04_setup_samba.sh`
- `deploy-rhel/05_deploy_portal.sh`
- `config/sshd_config` (現有 + Linux 路徑)
- `config/samba/smb.conf`
- `config/nginx/sf-portal.conf`
- `config/sssd/sssd.conf`

### 方向 B: 維持 Windows

繼續用我給的 patch 跑, 但會慢一點。

---

## 對應 SKILL / 文件

- 鐵律 9: 本文件本身是 runbook (eval 類型)
- 如果改 RHEL → 新建 `docs/RHEL_DEPLOYMENT.md` 取代部分 startup_sop.md
- AD 接法外加 `docs/AD_INTEGRATION.md`

---

## 給主管的一頁簡報 (你可以直接用)

```
主題: 將 SF 主機從 Windows Server 2022 改為 RHEL 9

理由:
1. 開發團隊 Linux 背景, 維護成本低
2. 功能 100% 對等主管圖規畫 (見對照表)
3. 金融業 RHEL 規範完整 (CIS / STIG)
4. License: RHEL 訂閱 vs Windows 授權, 視公司既有合約決定
5. 整合 AD 用 realm/sssd (RHEL 原生支援, 一行加入)

風險:
1. SMB + AD 整合需驗證 (Samba 4 成熟, 可控)
2. PAM 系統 agent 需確認支援 Linux
3. 公司 DB MSSQL → Linux pyodbc 連 (Microsoft 官方支援)

建議:
- PoC 階段先試 RHEL 1 週
- 確認所有功能 OK 後再決定正式
- 不行就回 Windows, 沒損失
```

---

## 結論

✅ **RHEL 可行, 推薦改**

下一步:
1. 你跟主管 / IT 確認可否
2. 確認後跟我說, 我寫 RHEL 部署 SOP
3. 如果有阻礙 (PAM agent / DB driver) 跟我說, 我評估替代方案
