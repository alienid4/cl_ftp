<#
.SYNOPSIS
    [Linux 用戶友善] PoC 一鍵部署: 純 C:\, 無 HTTPS, 從零到 Portal 可訪問。
.DESCRIPTION
    跑這一支 = 做完之前 A~H 全部步驟:
    - 切到 C:\ (不用 D:)
    - SQL DB 重建在 C:\_portal\db\
    - 重啟 sshd
    - 開防火牆 5000 port
    - 部署 Portal (Flask + waitress)
    - 註冊成 Windows Service (NSSM)
    - 顯示訪問網址

    Linux 對照: 就像跑 `./setup-poc.sh` 一樣, 一行解決
.PARAMETER SfBundleDir
    SF bundle 目錄, 預設 $env:USERPROFILE\Desktop\sf_offline_bundle_20260519_0901
.PARAMETER SkipPortal
    跳過 Portal Flask 部署 (沒抓 wheels 時用)
.PARAMETER DryRun
    只列出將執行的動作
.EXAMPLE
    .\poc_setup_c_drive.ps1
.EXAMPLE
    # 沒抓 wheels, 先做別的
    .\poc_setup_c_drive.ps1 -SkipPortal
#>
[CmdletBinding()]
param(
    [string]$SfBundleDir,
    [switch]$SkipPortal,
    [switch]$DryRun
)

$ErrorActionPreference = 'Continue'

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  SF PoC 一鍵部署 (C:\ 版, 無 HTTPS)" -ForegroundColor Cyan
Write-Host "  Linux 用戶友善版" -ForegroundColor DarkCyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

# 偵測 SF bundle
if (-not $SfBundleDir) {
    $candidates = @(
        "$env:USERPROFILE\Desktop\sf_offline_bundle_20260519_0901",
        "$env:USERPROFILE\OneDrive\桌面\sf_offline_bundle_20260519_0901",
        "C:\install\sf_offline_bundle_20260519_0901",
        "D:\install\sf_offline_bundle_20260519_0901"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { $SfBundleDir = $c; break }
    }
    if (-not $SfBundleDir) {
        Write-Host "[FAIL] 找不到 sf_offline_bundle_*. 請帶 -SfBundleDir <path>" -ForegroundColor Red
        exit 1
    }
}

Write-Host "[ok] SF bundle: $SfBundleDir" -ForegroundColor Green
Write-Host ""

# ===== Step A: 改 SQL schema D: → C: =====
Write-Host "[Step A] 改 SQL schema 路徑 D: → C: (Linux 對照: sed -i 's/...//' ...)" -ForegroundColor Yellow
$sqlFile = Join-Path $SfBundleDir 'sql\01_create_db.sql'
if (Test-Path $sqlFile) {
    if (-not $DryRun) {
        $content = Get-Content $sqlFile -Raw
        if ($content -match 'D:\\_portal') {
            $newContent = $content -replace 'D:\\_portal', 'C:\_portal'
            Set-Content $sqlFile -Value $newContent -Encoding UTF8
            Write-Host "  [ok] D:\_portal 改成 C:\_portal" -ForegroundColor Green
        } else {
            Write-Host "  [skip] 已是 C:\_portal" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "  [dry] $sqlFile" -ForegroundColor Gray
    }
} else {
    Write-Host "  [warn] $sqlFile 不存在" -ForegroundColor Yellow
}

# ===== Step B: 建目錄 C:\DataExchange + C:\_portal =====
Write-Host ""
Write-Host "[Step B] 建目錄 (Linux 對照: mkdir -p /data /portal)" -ForegroundColor Yellow
$dir01 = Join-Path $SfBundleDir 'deploy\01_setup_directories.ps1'
if (Test-Path $dir01) {
    if (-not $DryRun) {
        & $dir01 -DataRoot 'C:\DataExchange' -PortalRoot 'C:\_portal'
    } else {
        Write-Host "  [dry] $dir01 -DataRoot C:\... -PortalRoot C:\..." -ForegroundColor Gray
    }
} else {
    Write-Host "  [warn] 01_setup_directories.ps1 不存在, 手動 mkdir" -ForegroundColor Yellow
    if (-not $DryRun) {
        @('C:\DataExchange\HR\inbound', 'C:\DataExchange\HR\pending', 'C:\DataExchange\HR\outbound',
          'C:\DataExchange\HR\archive', 'C:\DataExchange\HR\error',
          'C:\DataExchange\FIN\inbound', 'C:\DataExchange\FIN\pending', 'C:\DataExchange\FIN\outbound',
          'C:\DataExchange\FIN\archive', 'C:\DataExchange\FIN\error',
          'C:\DataExchange\OPS\inbound', 'C:\DataExchange\OPS\pending', 'C:\DataExchange\OPS\outbound',
          'C:\DataExchange\OPS\archive', 'C:\DataExchange\OPS\error',
          'C:\DataExchange\samba',
          'C:\_portal\app', 'C:\_portal\logs', 'C:\_portal\db',
          'C:\_portal\scripts', 'C:\_portal\backups', 'C:\_portal\ftps_pasv',
          'C:\install', 'C:\install\python_wheels'
        ) | ForEach-Object {
            New-Item -Path $_ -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
        }
        Write-Host "  [ok] 目錄結構建立完成" -ForegroundColor Green
    }
}

# ===== Step C: 設 NTFS ACL =====
Write-Host ""
Write-Host "[Step C] 設權限 (Linux 對照: chown / chmod)" -ForegroundColor Yellow
$dir02 = Join-Path $SfBundleDir 'deploy\02_setup_ntfs_acl.ps1'
if (Test-Path $dir02) {
    if (-not $DryRun) {
        & $dir02 -DataRoot 'C:\DataExchange' -PortalRoot 'C:\_portal'
    } else {
        Write-Host "  [dry] $dir02" -ForegroundColor Gray
    }
}

# ===== Step D: 重建 SQL DB =====
Write-Host ""
Write-Host "[Step D] 重建 SQL DB (Linux 對照: mysql -u root -p < schema.sql)" -ForegroundColor Yellow
$sqlcmd = "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\SQLCMD.EXE"
if (Test-Path $sqlcmd) {
    if (-not $DryRun) {
        Write-Host "  Drop 舊 DB (如果在 D:\)..."
        & $sqlcmd -S '.\SQLEXPRESS' -E -Q "IF DB_ID('FileExchangeAudit') IS NOT NULL DROP DATABASE FileExchangeAudit;" 2>&1 | Out-Null

        Write-Host "  Create 新 DB (在 C:\_portal\db\)..."
        & $sqlcmd -S '.\SQLEXPRESS' -E -i $sqlFile 2>&1 | Tee-Object -Variable sqlOutput | Out-Null
        if ($sqlOutput -match 'error|level 16') {
            Write-Host "  [warn] SQL 有警告, 但 DB 應已建立" -ForegroundColor Yellow
        } else {
            Write-Host "  [ok] DB 重建完成" -ForegroundColor Green
        }
    } else {
        Write-Host "  [dry] sqlcmd -i $sqlFile" -ForegroundColor Gray
    }
} else {
    Write-Host "  [warn] 找不到 sqlcmd: $sqlcmd" -ForegroundColor Yellow
}

# ===== Step E: 重啟 sshd =====
Write-Host ""
Write-Host "[Step E] 重啟 sshd (Linux 對照: systemctl restart sshd)" -ForegroundColor Yellow
$dir03 = Join-Path $SfBundleDir 'deploy\03_install_openssh.ps1'
if (Test-Path $dir03) {
    if (-not $DryRun) {
        & $dir03
    }
} else {
    # 簡化版: 直接 restart
    if (-not $DryRun) {
        try {
            Restart-Service sshd -ErrorAction Stop
            Write-Host "  [ok] sshd 重啟" -ForegroundColor Green
        } catch {
            Write-Host "  [warn] sshd 重啟失敗: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

# ===== Step F: 開防火牆 5000 port =====
Write-Host ""
Write-Host "[Step F] 開防火牆 5000 port (Linux 對照: firewall-cmd --add-port=5000/tcp)" -ForegroundColor Yellow
if (-not $DryRun) {
    $existing = Get-NetFirewallRule -Name 'FX-PortalHTTP-5000-In' -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "  [skip] 規則已存在" -ForegroundColor DarkGray
    } else {
        New-NetFirewallRule -Name 'FX-PortalHTTP-5000-In' `
            -DisplayName 'FileExchange Portal HTTP (PoC, no TLS)' `
            -Direction Inbound -Protocol TCP -LocalPort 5000 `
            -Action Allow -Enabled True -RemoteAddress '10.0.0.0/8' | Out-Null
        Write-Host "  [ok] 防火牆規則建立 (5000 內網 10.0.0.0/8 可進)" -ForegroundColor Green
    }
}

# ===== Step G: 部署 Portal (如果有 wheels) =====
Write-Host ""
Write-Host "[Step G] 部署 Portal (Linux 對照: pip install -r requirements.txt + 啟 wsgi)" -ForegroundColor Yellow
if ($SkipPortal) {
    Write-Host "  [skip] -SkipPortal 指定, 跳過" -ForegroundColor DarkGray
    Write-Host "  之後抓 wheels 後再跑: .\poc_setup_c_drive.ps1 (不帶 -SkipPortal)" -ForegroundColor Cyan
} else {
    $wheelsDir = 'C:\install\python_wheels'
    $hasWheels = (Test-Path $wheelsDir) -and ((Get-ChildItem $wheelsDir -Filter '*.whl' -ErrorAction SilentlyContinue).Count -gt 0)
    if (-not $hasWheels) {
        Write-Host "  [warn] $wheelsDir 沒有 wheels, 跳過 Portal 部署" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  外網 PC 抓 wheels:" -ForegroundColor Cyan
        Write-Host "    mkdir C:\Temp\sf_wheels"
        Write-Host "    cd C:\Temp\sf_wheels"
        Write-Host "    pip download flask waitress pyodbc python-ldap requests"
        Write-Host "  USB 拷到 SF 主機 $wheelsDir 後重跑本腳本"
        $SkipPortal = $true
    } else {
        Write-Host "  [ok] 找到 wheels: $wheelsDir" -ForegroundColor Green
        $dir09 = Join-Path $SfBundleDir 'deploy\09_setup_portal.ps1'
        if (Test-Path $dir09) {
            if (-not $DryRun) {
                & $dir09 -PortalTarget 'C:\_portal\app'
            }
        }
    }
}

# ===== Step H: 註冊 Portal 為 Service (NSSM) =====
if (-not $SkipPortal) {
    Write-Host ""
    Write-Host "[Step H] 註冊 Portal Service (Linux 對照: systemctl enable + start)" -ForegroundColor Yellow
    $nssm = 'C:\Tools\nssm.exe'
    $waitress = 'C:\_portal\app\.venv\Scripts\waitress-serve.exe'
    if ((Test-Path $nssm) -and (Test-Path $waitress)) {
        if (-not $DryRun) {
            $svc = Get-Service FileExchangePortal -ErrorAction SilentlyContinue
            if ($svc) {
                Write-Host "  [skip] Service FileExchangePortal 已存在" -ForegroundColor DarkGray
            } else {
                & $nssm install FileExchangePortal $waitress 2>&1 | Out-Null
                & $nssm set FileExchangePortal AppParameters "--host=0.0.0.0 --port=5000 --call wsgi:create_app" 2>&1 | Out-Null
                & $nssm set FileExchangePortal AppDirectory 'C:\_portal\app' 2>&1 | Out-Null
                & $nssm set FileExchangePortal Start SERVICE_AUTO_START 2>&1 | Out-Null
                & $nssm set FileExchangePortal DisplayName "FileExchange Portal (Flask)" 2>&1 | Out-Null
                Write-Host "  [ok] FileExchangePortal service 已註冊"
                try {
                    Start-Service FileExchangePortal -ErrorAction Stop
                    Write-Host "  [ok] FileExchangePortal 已啟動" -ForegroundColor Green
                } catch {
                    Write-Host "  [warn] 啟動失敗: $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
        }
    } else {
        Write-Host "  [warn] nssm 或 waitress-serve 不存在, 跳過 service 註冊" -ForegroundColor Yellow
    }
}

# ===== 總結: 看服務 + 給訪問網址 =====
Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  完成!以下是部署結果 (Linux 對照: systemctl status / ip a)" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

# 服務狀態
Write-Host "服務狀態:" -ForegroundColor Yellow
Get-Service sshd, 'MSSQL$SQLEXPRESS', W3SVC, FileExchangePortal -ErrorAction SilentlyContinue |
    Format-Table Name, Status, StartType -AutoSize

# Port 監聽
Write-Host "Port 監聽 (Linux 對照: netstat -tlnp):" -ForegroundColor Yellow
$listeningPorts = @(22, 1433, 5000, 443, 445)
foreach ($p in $listeningPorts) {
    $conn = Get-NetTCPConnection -State Listen -LocalPort $p -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($conn) {
        Write-Host "  TCP $p`t[ok] 監聽中" -ForegroundColor Green
    } else {
        Write-Host "  TCP $p`t[--] 未監聽" -ForegroundColor DarkGray
    }
}

# IP / 訪問網址
Write-Host ""
Write-Host "IP 位址 (Linux 對照: ip a):" -ForegroundColor Yellow
$ips = (Get-NetIPAddress -AddressFamily IPv4 -PrefixOrigin Manual, Dhcp -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike '169.*' -and $_.IPAddress -ne '127.0.0.1' }).IPAddress
if (-not $ips) {
    $ips = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike '169.*' -and $_.IPAddress -ne '127.0.0.1' }).IPAddress
}
foreach ($ip in $ips) {
    Write-Host "  $ip" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "訪問網址:" -ForegroundColor Yellow
$mainIp = $ips | Select-Object -First 1
if ($mainIp) {
    Write-Host "  Portal HTTP    : http://$mainIp`:5000/         (給 OA USER 用瀏覽器)" -ForegroundColor Cyan
    Write-Host "  SFTP           : sftp <user>@$mainIp           (給 AP 系統, 帳號未建)" -ForegroundColor Cyan
    Write-Host "  SMB            : \\$mainIp\samba\<dept>\        (給 OA USER, samba share 未配)" -ForegroundColor Cyan
    Write-Host "  RDP            : mstsc /v:$mainIp              (給 IT 維運)" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  Linux 對照備忘 (寫在腦中)" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host @"

  Linux                              | Windows
  -----------------------------------|----------------------------------------
  systemctl status sshd              | Get-Service sshd
  systemctl restart sshd             | Restart-Service sshd
  systemctl enable sshd              | Set-Service sshd -StartupType Automatic
  journalctl -u sshd -n 50           | Get-EventLog -LogName Application -Source OpenSSH -Newest 50
  netstat -tlnp                      | Get-NetTCPConnection -State Listen
  ip a                               | Get-NetIPAddress
  vi /etc/ssh/sshd_config            | notepad C:\ProgramData\ssh\sshd_config
  cat /etc/hostname                  | hostname
  ps aux                             | Get-Process
  top                                | Get-Process | sort CPU -desc | select -first 10
  iptables -L                        | Get-NetFirewallRule | where Enabled -eq True
  useradd user1                      | New-LocalUser user1
  crontab -l                         | Get-ScheduledTask
  df -h                              | Get-PSDrive
  tail -f file.log                   | Get-Content file.log -Tail 50 -Wait
"@ -ForegroundColor DarkGray

Write-Host ""
Write-Host "完整指南: docs/LINUX_USER_GUIDE.md" -ForegroundColor Cyan
