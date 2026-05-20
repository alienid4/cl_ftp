# Linux 用戶速查 — SF 主機 (Windows Server) 對照指南

> 你會 Linux, 不熟 Windows? 看這份就夠了。所有 Linux 指令都有 Windows 對照。

---

## 🚀 一鍵 PoC 部署 (對應 Linux 的 `./setup.sh`)

```powershell
# 在 SF 主機 (PowerShell, 系統管理員)
cd C:\Users\xxx\Desktop\sf_offline_bundle_*\scripts
.\poc_setup_c_drive.ps1
```

完成後直接顯示訪問網址。

---

## 概念對照表

| Linux 概念 | Windows 對應 | 註解 |
|---|---|---|
| `systemd / init.d` | **Windows Services** (`services.msc`) | 服務管理 |
| `/etc/` (設定檔) | `C:\ProgramData\` (大多) / `C:\Windows\System32\` | 系統設定 |
| `/var/log/` | `Event Viewer` + 各 app 自己的 log 目錄 | log |
| `/etc/passwd` | `lusrmgr.msc` 或 PowerShell `Get-LocalUser` | 本機帳號 |
| `chown / chmod` | **NTFS ACL** (`icacls` 或 PowerShell `Set-Acl`) | 權限 |
| `iptables / firewalld` | **Windows Firewall** (`Get-NetFirewallRule`) | 防火牆 |
| `apt / yum` | `winget` / `choco` / 手動 `.msi` | 套件管理 |
| `cron` | **Task Scheduler** (`taskschd.msc`) | 排程 |
| `bash` | **PowerShell** (PS) — 但語法不同 | shell |
| `/etc/hosts` | `C:\Windows\System32\drivers\etc\hosts` | 同一個 |
| `sudo` | **Run as Administrator** (UAC) | 提權 |
| `root` 帳號 | **Administrator** 帳號 | 超級用戶 |
| `/opt/` 或 `/usr/local/` | `C:\Program Files\` | 套件安裝位置 |
| `/home/user/` | `C:\Users\<user>\` | 家目錄 |
| `/tmp/` | `%TEMP%` 或 `C:\Windows\Temp\` | 暫存 |

---

## Linux 指令 → Windows 對照 (常用)

### 服務管理

```bash
# Linux
systemctl status sshd
systemctl start sshd
systemctl stop sshd
systemctl restart sshd
systemctl enable sshd        # 開機自啟動
systemctl disable sshd
systemctl list-units --type=service
```

```powershell
# Windows
Get-Service sshd
Start-Service sshd
Stop-Service sshd
Restart-Service sshd
Set-Service sshd -StartupType Automatic
Set-Service sshd -StartupType Disabled
Get-Service | Where-Object { $_.Status -eq 'Running' }
```

### 看 log

```bash
# Linux
tail -f /var/log/messages
tail -f /var/log/auth.log
journalctl -u sshd -n 50
journalctl -u sshd -f
```

```powershell
# Windows
Get-Content C:\path\to\app.log -Tail 50 -Wait

# Event Log (取代 syslog/journald)
Get-EventLog -LogName Application -Newest 50
Get-EventLog -LogName System -Newest 50

# OpenSSH log
Get-WinEvent -LogName 'OpenSSH/Operational' -MaxEvents 50

# Tail 形式 (持續看)
Get-WinEvent -LogName Application -MaxEvents 10 |
    Format-Table TimeCreated, ProviderName, Message -AutoSize
```

### 網路

```bash
# Linux
ip a
ip route
netstat -tlnp                # 看開哪些 port
ss -tlnp
ping 8.8.8.8
traceroute google.com
curl http://localhost:5000
```

```powershell
# Windows
ipconfig                     # 簡單版
Get-NetIPAddress             # 詳細版
Get-NetRoute
Get-NetTCPConnection -State Listen   # 看開哪些 port (netstat)
Test-NetConnection google.com -Port 443   # ping + port test
Test-NetConnection localhost -Port 5000
Invoke-WebRequest http://localhost:5000
```

### 防火牆

```bash
# Linux (firewalld)
firewall-cmd --list-all
firewall-cmd --add-port=5000/tcp --permanent
firewall-cmd --reload
firewall-cmd --remove-port=5000/tcp --permanent

# Linux (iptables)
iptables -L -n
iptables -A INPUT -p tcp --dport 5000 -j ACCEPT
```

```powershell
# Windows
Get-NetFirewallRule | Where-Object Enabled -eq True | Format-Table DisplayName, Direction
New-NetFirewallRule -Name 'MyApp-5000' -DisplayName 'MyApp HTTP' `
    -Direction Inbound -Protocol TCP -LocalPort 5000 -Action Allow `
    -RemoteAddress '10.0.0.0/8'   # 限內網來源
Remove-NetFirewallRule -Name 'MyApp-5000'
```

### 帳號 / 權限

```bash
# Linux
useradd -m alice
passwd alice
usermod -aG sudo alice       # 加 sudo 群組
chown alice:users /data/dir
chmod 755 /data/dir
chmod -R g+rw /data/dir
```

```powershell
# Windows
New-LocalUser -Name alice -Password (Read-Host -AsSecureString)
Set-LocalUser -Name alice -Password (Read-Host -AsSecureString)
Add-LocalGroupMember -Group 'Administrators' -Member alice

# NTFS ACL
icacls C:\data /grant 'alice:M'   # M = Modify (相當於 7)
icacls C:\data /grant 'alice:RX'  # RX = Read+Execute (相當於 5)
icacls C:\data /inheritance:r     # 不繼承父原則

# PowerShell 版
$acl = Get-Acl C:\data
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule('alice','Modify','Allow')
$acl.AddAccessRule($rule)
Set-Acl C:\data -AclObject $acl
```

### Process 管理

```bash
# Linux
ps aux | grep python
top
htop
kill 1234
killall python
```

```powershell
# Windows
Get-Process | Where-Object { $_.ProcessName -like '*python*' }
Get-Process | Sort-Object CPU -Descending | Select-Object -First 10
Stop-Process -Id 1234 -Force
Stop-Process -Name python -Force
```

### 磁碟 / 檔案

```bash
# Linux
df -h
du -sh /data
ls -la /data
find /data -name '*.log' -mtime +7
tar czf backup.tgz /data
cat file.txt
grep 'error' /var/log/app.log
sed -i 's/old/new/g' file.txt
```

```powershell
# Windows
Get-PSDrive | Where-Object { $_.Provider -like '*FileSystem*' } | Format-Table Name, Used, Free
Get-ChildItem C:\data -Recurse | Measure-Object -Property Length -Sum
Get-ChildItem C:\data
Get-ChildItem C:\data -Recurse -Filter '*.log' | Where-Object LastWriteTime -lt (Get-Date).AddDays(-7)
Compress-Archive C:\data -DestinationPath C:\backup.zip
Get-Content file.txt
Select-String 'error' C:\path\app.log
# sed 在 PS:
(Get-Content file.txt) -replace 'old', 'new' | Set-Content file.txt
```

### 排程 (cron)

```bash
# Linux
crontab -l
crontab -e
# Cron 範例: 每天凌晨 1 點跑備份
# 0 1 * * * /usr/local/bin/backup.sh
```

```powershell
# Windows
Get-ScheduledTask
Get-ScheduledTask -TaskName SF_DailyBackup | Get-ScheduledTaskInfo

# 建排程
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-File C:\backup.ps1'
$trigger = New-ScheduledTaskTrigger -Daily -At 1:00am
Register-ScheduledTask -Action $action -Trigger $trigger -TaskName 'DailyBackup' -RunLevel Highest -User 'SYSTEM'
```

### 環境變數

```bash
# Linux
export PATH=$PATH:/opt/bin
echo $PATH
env
source ~/.bashrc
```

```powershell
# Windows (PowerShell)
$env:PATH                                   # 顯示
$env:PATH += ';C:\NewTool\bin'              # 暫時加 (這 session)

# 永久加 (要 admin)
[Environment]::SetEnvironmentVariable('PATH', "$env:PATH;C:\NewTool\bin", 'Machine')

Get-ChildItem env:                          # env
```

### 編輯設定檔

```bash
# Linux
vi /etc/ssh/sshd_config
nano /etc/nginx/nginx.conf
```

```powershell
# Windows
notepad C:\ProgramData\ssh\sshd_config      # 簡單編輯
notepad++ C:\ProgramData\ssh\sshd_config    # 如果裝了 Notepad++

# 進階: 用 vim (Windows 版)
# 安裝: choco install vim
# 或裝 WSL 直接用 Linux vim

# PowerShell 一行改檔 (像 sed)
(Get-Content C:\ProgramData\ssh\sshd_config -Raw) `
    -replace 'sftp-server.exe', 'internal-sftp' `
    | Set-Content C:\ProgramData\ssh\sshd_config -Encoding ASCII
```

---

## SF 主機特定 — 你需要記的 5 個指令

### 1. 看所有 SF 服務

```powershell
Get-Service sshd, 'MSSQL$SQLEXPRESS', W3SVC, LanmanServer, W32Time, FileExchangePortal -ErrorAction SilentlyContinue |
    Format-Table Name, Status, StartType -AutoSize
```

### 2. 重啟 sshd (改完 sshd_config)

```powershell
notepad C:\ProgramData\ssh\sshd_config  # 改
Restart-Service sshd                     # 重啟
Get-Service sshd                          # 確認 Running
```

### 3. 看 sshd log (失敗排查)

```powershell
Get-WinEvent -LogName 'OpenSSH/Operational' -MaxEvents 20 |
    Format-Table TimeCreated, LevelDisplayName, Message -Wrap
```

### 4. 看 Portal log

```powershell
Get-Content C:\_portal\logs\portal.log -Tail 100 -Wait
# 或從 NSSM service stdout/stderr
Get-Content C:\_portal\logs\portal-stdout.log -Tail 100 -Wait
```

### 5. 一鍵健康檢查

```powershell
cd C:\Users\xxx\Desktop\sf_offline_bundle_*\scripts
.\health_check.ps1
```

→ 彩色清單告訴你哪些 ✅, 哪些 ❌

---

## 常見「Linux 都這樣做為何 Windows 不行」對照

| 你想做 | Linux | Windows 對應 |
|---|---|---|
| 切換用戶執行 | `sudo -u www-data cmd` | `runas /user:DOMAIN\user cmd` 或 `Invoke-Command -Credential $cred` |
| 看 process 開哪些 port | `lsof -i :5000` | `Get-NetTCPConnection -LocalPort 5000` |
| 殺占 port 的 process | `fuser -k 5000/tcp` | `Get-NetTCPConnection -LocalPort 5000 \| % { Stop-Process -Id $_.OwningProcess }` |
| 改 hostname | `hostnamectl set-hostname newname` | `Rename-Computer -NewName newname` (要 reboot) |
| 看開機自啟動 | `systemctl list-unit-files --state=enabled` | `Get-Service \| where StartType -eq Automatic` |
| 設定 DNS | `vi /etc/resolv.conf` | `Set-DnsClientServerAddress -InterfaceAlias Ethernet -ServerAddresses 8.8.8.8` |
| 重新啟動 | `shutdown -r now` 或 `reboot` | `shutdown /r /t 0` 或 `Restart-Computer -Force` |
| 看誰登入 | `who` / `last` | `query user` 或 `Get-EventLog Security -InstanceId 4624` |
| Symlink | `ln -s /path/target /path/link` | `New-Item -ItemType SymbolicLink -Path link -Target target` (admin) |
| 字串比對 | `grep`, `awk` | `Select-String`, `Where-Object`, `-match` 運算子 |

---

## 常見問題

### Q: PowerShell 怎麼讓 script 可執行?

Linux: `chmod +x script.sh`
Windows: `Set-ExecutionPolicy Bypass -Scope Process` (這個 session 內)

或永久放寬 (要 admin):
```powershell
Set-ExecutionPolicy RemoteSigned -Scope LocalMachine
```

### Q: 怎麼當作 daemon 跑?

Linux: systemd unit file
Windows: 用 **NSSM** 把 .exe / python 包成 service

```powershell
nssm install MyApp 'C:\path\to\python.exe'
nssm set MyApp AppParameters 'C:\path\to\app.py'
nssm set MyApp AppDirectory 'C:\path\to'
nssm set MyApp Start SERVICE_AUTO_START
nssm start MyApp
```

### Q: 怎麼看「為什麼 service 沒啟動」?

Linux: `journalctl -u sshd -n 50` 或 `systemctl status sshd`
Windows:
```powershell
Get-WinEvent -LogName Application -MaxEvents 50 |
    Where-Object { $_.ProviderName -like '*OpenSSH*' -or $_.LevelDisplayName -eq 'Error' } |
    Format-Table TimeCreated, ProviderName, Message -Wrap
```

或 GUI: 開 `eventvwr.msc` → Windows Logs → Application

### Q: 配置檔被改壞了, 怎麼還原?

我們的腳本每次改設定都會備份, 找 `.bak.<timestamp>` 檔:
```powershell
ls C:\ProgramData\ssh\*.bak.*
# 還原
Copy-Item 'C:\ProgramData\ssh\sshd_config.bak.20260520_083034' `
          'C:\ProgramData\ssh\sshd_config' -Force
Restart-Service sshd
```

---

## 我覺得最不直覺的 5 個 Windows 事

1. **大小寫不分** — `C:\Users` 跟 `c:\users` 是同一個東西 (跟 Linux 不同)
2. **路徑分隔符 `\`** — Linux `/`, Windows `\`, 但 PowerShell 兩個都吃
3. **沒有 `tee /dev/stdout`** — PowerShell 用 `Tee-Object` 但行為略不同
4. **service 不是進程** — Linux service 就是 process, Windows service 跟 process 是兩件事 (service 包 process)
5. **執行權限** — Linux `chmod +x`, Windows 看副檔名 + ExecutionPolicy + 數位簽章

---

## 找不到指令時怎麼辦?

```powershell
# 找指令 (像 Linux apropos / which)
Get-Command *firewall*
Get-Command Restart-*
which-like-command-name
```

或上網搜尋: `<想做的事> powershell` (Stack Overflow 答案通常很好)。

或問我, 我可以幫你把 Linux 指令翻成 Windows 等價的。

---

## 速查: SF 主機所有重要路徑

| 物件 | 路徑 |
|---|---|
| sshd 設定 | `C:\ProgramData\ssh\sshd_config` |
| sshd binary | `C:\Program Files\OpenSSH\sshd.exe` |
| sshd log | `Get-WinEvent -LogName 'OpenSSH/Operational'` |
| 業務檔 | `C:\DataExchange\<dept>\inbound\` (或 D:\) |
| Portal 程式碼 | `C:\_portal\app\` (或 D:\) |
| Portal venv | `C:\_portal\app\.venv\` |
| Portal log | `C:\_portal\logs\` |
| SQL DB | `C:\_portal\db\FileExchangeAudit.mdf` |
| NSSM | `C:\Tools\nssm.exe` |
| 排程腳本 | `C:\_portal\scripts\` |
| 防火牆 log | `C:\Windows\System32\LogFiles\Firewall\pfirewall.log` |
| 部署 bundle | `C:\install\sf_offline_bundle_*\` (建議搬這, 別放桌面) |
