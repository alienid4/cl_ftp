<#
.SYNOPSIS
    [內網 SF 主機] 用 PowerShell Team Win32-OpenSSH portable zip 安裝 OpenSSH, 不需要 FoD / ISO / sxs。
.DESCRIPTION
    解決 install_offline.ps1 Step 7 OpenSSH 失敗 (0x800f0907, 內網無 FoD source) 的最快路。

    Win32-OpenSSH 是 PowerShell Team 官方維護的 portable 版本, 跟 Windows FoD 版本同源,
    但只有 5 MB zip, 不依賴 Windows Update / WSUS / FoD CAB。

    用法 (3 步):
      1. 外網抓 https://github.com/PowerShell/Win32-OpenSSH/releases/latest
         下載 OpenSSH-Win64.zip (約 5 MB)
      2. USB 拷到 SF 主機
      3. 跑這支, 帶 -ZipPath 指向 zip 檔

    idempotent: 已裝就 skip, 重跑無害。
.PARAMETER ZipPath
    OpenSSH-Win64.zip 的完整路徑, 例: 'D:\install\OpenSSH-Win64.zip'。
    若不指定, 會自動掃描以下位置找 OpenSSH-Win64*.zip:
      1. 當前目錄
      2. 腳本所在目錄
      3. C:\ClaudeHome\, D:\install\, D:\, C:\Temp\, $HOME\Downloads\
.PARAMETER InstallDir
    安裝目錄 (預設: 'C:\Program Files\OpenSSH')
.PARAMETER DryRun
    只列出將執行的動作, 不實際做事。
.EXAMPLE
    # 自動找 zip
    .\install_openssh_portable.ps1
.EXAMPLE
    # 指定 zip 路徑
    .\install_openssh_portable.ps1 -ZipPath 'D:\install\OpenSSH-Win64.zip'
.EXAMPLE
    # 預演
    .\install_openssh_portable.ps1 -DryRun
.NOTES
    Patch: v1.0.0.5 (基礎) / v1.0.0.6 (auto-find zip)
    Win32-OpenSSH 下載: https://github.com/PowerShell/Win32-OpenSSH/releases
    對應 issue: docs/dev-log/issues_log.md #010
#>
[CmdletBinding()]
param(
    [string]$ZipPath,

    [string]$InstallDir = 'C:\Program Files\OpenSSH',

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

Write-Host "`n=== OpenSSH Portable Installer (Win32-OpenSSH) ===" -ForegroundColor Cyan
Write-Host "Patch v1.0.0.5 - 用 portable zip 裝 OpenSSH, 不需 FoD" -ForegroundColor DarkCyan

# ===== Step 0: 必要檢查 =====
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[FAIL] 必須用系統管理員 PowerShell 跑" -ForegroundColor Red
    exit 1
}

# ===== Step 1: 已裝偵測 =====
Write-Host ""
Write-Host "[1/6] 已裝偵測..." -ForegroundColor Yellow

$sshSvc = Get-Service sshd -ErrorAction SilentlyContinue
$installSshd = Join-Path $InstallDir 'install-sshd.ps1'
$sshdExe = Join-Path $InstallDir 'sshd.exe'

if ($sshSvc -and (Test-Path $sshdExe)) {
    Write-Host "[skip] sshd service 已存在, 安裝目錄: $InstallDir" -ForegroundColor Green
    Write-Host ""
    Write-Host "現有狀態:"
    Get-Service sshd, ssh-agent -ErrorAction SilentlyContinue | Format-Table Name, Status, StartType -AutoSize

    # 仍嘗試確保啟動 + 開機自啟動 (idempotent)
    if (-not $DryRun) {
        if ($sshSvc.StartType -ne 'Automatic') {
            Set-Service sshd -StartupType Automatic
            Write-Host "[fix] 已設為 Automatic 啟動" -ForegroundColor Yellow
        }
        if ($sshSvc.Status -ne 'Running') {
            Start-Service sshd
            Write-Host "[fix] 已啟動 sshd" -ForegroundColor Yellow
        }
    }

    Write-Host ""
    Write-Host "驗證 port 22:"
    Test-NetConnection -ComputerName localhost -Port 22 -WarningAction SilentlyContinue |
        Select-Object ComputerName, RemotePort, TcpTestSucceeded | Format-Table -AutoSize

    exit 0
}

# ===== Step 2: 驗證/自動找 zip =====
Write-Host ""
Write-Host "[2/6] 取得 ZIP..." -ForegroundColor Yellow

if (-not $ZipPath) {
    # Auto-find zip
    $searchDirs = @(
        (Get-Location).Path,                          # 當前目錄
        $PSScriptRoot,                                # 腳本所在目錄
        'C:\ClaudeHome',
        'D:\install',
        'D:\',
        'C:\Temp',
        (Join-Path $HOME 'Downloads')
    ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique

    Write-Host "[auto] 未指定 -ZipPath, 自動掃描:"
    foreach ($dir in $searchDirs) {
        Write-Host "       - $dir"
        $candidates = Get-ChildItem $dir -Filter 'OpenSSH-Win64*.zip' -File -ErrorAction SilentlyContinue
        if ($candidates) {
            $ZipPath = $candidates[0].FullName
            Write-Host "[ok] 找到: $ZipPath" -ForegroundColor Green
            break
        }
    }

    if (-not $ZipPath) {
        Write-Host ""
        Write-Host "[FAIL] 找不到 OpenSSH-Win64*.zip" -ForegroundColor Red
        Write-Host ""
        Write-Host "取得方式:" -ForegroundColor Yellow
        Write-Host "  1. 外網 PC 抓 https://github.com/PowerShell/Win32-OpenSSH/releases/latest"
        Write-Host "  2. 下載 OpenSSH-Win64.zip (約 5 MB)"
        Write-Host "  3. USB 拷到 SF 主機, 放當前目錄 / D:\install\ / D:\ / C:\ClaudeHome\ 任一處"
        Write-Host "  4. 重跑本腳本 (不用帶參數)"
        Write-Host "  或: 用 fetch_openssh_portable.ps1 (外網 PC 一鍵抓 + 算 SHA256)"
        exit 1
    }
}

if (-not (Test-Path $ZipPath)) {
    Write-Host "[FAIL] ZIP 不存在: $ZipPath" -ForegroundColor Red
    Write-Host ""
    Write-Host "需要 Win32-OpenSSH portable zip. 取得方式:" -ForegroundColor Yellow
    Write-Host "  1. 外網 PC 抓 https://github.com/PowerShell/Win32-OpenSSH/releases/latest"
    Write-Host "  2. 下載 OpenSSH-Win64.zip (約 5 MB)"
    Write-Host "  3. USB 拷到 SF 主機, 跑本腳本 -ZipPath '<路徑>'"
    exit 1
}

$zipSizeMB = '{0:N2}' -f ((Get-Item $ZipPath).Length / 1MB)
Write-Host "[ok] ZIP: $ZipPath ($zipSizeMB MB)"

# 快速 sanity check (zip 該長啥樣)
if ((Get-Item $ZipPath).Length -lt 1MB) {
    Write-Host "[warn] ZIP 異常小 ($zipSizeMB MB), 預期 ~5 MB. 可能下載不完整?" -ForegroundColor Yellow
}
if ((Get-Item $ZipPath).Length -gt 50MB) {
    Write-Host "[warn] ZIP 異常大 ($zipSizeMB MB), 預期 ~5 MB. 可能抓錯檔?" -ForegroundColor Yellow
}

# ===== Step 3: 解壓 =====
Write-Host ""
Write-Host "[3/6] 解壓到 $InstallDir..." -ForegroundColor Yellow

if (Test-Path $InstallDir) {
    $existingFiles = (Get-ChildItem $InstallDir -ErrorAction SilentlyContinue).Count
    if ($existingFiles -gt 0) {
        Write-Host "[warn] $InstallDir 已存在且非空 ($existingFiles 個檔)" -ForegroundColor Yellow
        if (-not $DryRun) {
            $bak = "$InstallDir.bak.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
            Write-Host "[backup] 備份到 $bak"
            Rename-Item $InstallDir $bak
        }
    }
}

if ($DryRun) {
    Write-Host "[dry] Expand-Archive '$ZipPath' -DestinationPath '<Program Files>' -Force"
    Write-Host "[dry] 預期解壓出 'OpenSSH-Win64\' 目錄, rename 為 'OpenSSH'"
} else {
    $tempExtract = Join-Path $env:TEMP "openssh_extract_$(Get-Random)"
    New-Item -Path $tempExtract -ItemType Directory -Force | Out-Null

    try {
        Expand-Archive -Path $ZipPath -DestinationPath $tempExtract -Force

        # zip 內通常是 OpenSSH-Win64\ 一層目錄, 找到它
        $extracted = Get-ChildItem $tempExtract -Directory | Select-Object -First 1
        if (-not $extracted) {
            Write-Host "[FAIL] zip 解壓後找不到任何目錄" -ForegroundColor Red
            exit 1
        }

        # 確認解壓內容含 sshd.exe + install-sshd.ps1
        $checkSshd = Join-Path $extracted.FullName 'sshd.exe'
        $checkInstaller = Join-Path $extracted.FullName 'install-sshd.ps1'
        if (-not (Test-Path $checkSshd) -or -not (Test-Path $checkInstaller)) {
            Write-Host "[FAIL] zip 內缺 sshd.exe 或 install-sshd.ps1" -ForegroundColor Red
            Write-Host "       這個 zip 可能不是 Win32-OpenSSH (抓錯版本?)"
            Write-Host "       正確來源: https://github.com/PowerShell/Win32-OpenSSH/releases"
            exit 1
        }

        # 搬到 InstallDir
        $parentDir = Split-Path $InstallDir -Parent
        if (-not (Test-Path $parentDir)) {
            New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
        }
        Move-Item $extracted.FullName $InstallDir -Force

        Remove-Item $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "[ok] 解壓完成: $InstallDir" -ForegroundColor Green
    } catch {
        Write-Host "[FAIL] 解壓失敗: $($_.Exception.Message)" -ForegroundColor Red
        Remove-Item $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
        exit 1
    }
}

# ===== Step 4: 跑 install-sshd.ps1 註冊 service =====
Write-Host ""
Write-Host "[4/6] 註冊 sshd service..." -ForegroundColor Yellow

if ($DryRun) {
    Write-Host "[dry] & '$InstallDir\install-sshd.ps1'"
} else {
    $installer = Join-Path $InstallDir 'install-sshd.ps1'
    if (-not (Test-Path $installer)) {
        Write-Host "[FAIL] 找不到 $installer" -ForegroundColor Red
        exit 1
    }

    try {
        & $installer
        Write-Host "[ok] sshd / ssh-agent service 已註冊" -ForegroundColor Green
    } catch {
        Write-Host "[FAIL] install-sshd.ps1 執行失敗: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

# ===== Step 5: 啟動 + 開機自啟動 =====
Write-Host ""
Write-Host "[5/6] 啟動 service + 設開機自啟動..." -ForegroundColor Yellow

if ($DryRun) {
    Write-Host "[dry] Set-Service sshd, ssh-agent -StartupType Automatic"
    Write-Host "[dry] Start-Service sshd"
} else {
    Set-Service sshd -StartupType Automatic
    Set-Service ssh-agent -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service sshd
    Write-Host "[ok] sshd 已啟動 + Automatic" -ForegroundColor Green
}

# ===== Step 6: 防火牆 =====
Write-Host ""
Write-Host "[6/6] 開防火牆 22 port..." -ForegroundColor Yellow

$fwRule = Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue
if ($fwRule) {
    if ($fwRule.Enabled -ne 'True') {
        if (-not $DryRun) {
            Enable-NetFirewallRule -Name 'OpenSSH-Server-In-TCP'
            Write-Host "[fix] 既有 rule 啟用" -ForegroundColor Yellow
        }
    } else {
        Write-Host "[skip] 防火牆 rule 已啟用" -ForegroundColor DarkGray
    }
} else {
    if ($DryRun) {
        Write-Host "[dry] New-NetFirewallRule OpenSSH-Server-In-TCP (TCP 22)"
    } else {
        New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' `
            -DisplayName 'OpenSSH Server (sshd)' `
            -Enabled True -Direction Inbound -Protocol TCP `
            -Action Allow -LocalPort 22 | Out-Null
        Write-Host "[ok] 新建防火牆 rule (TCP 22 入站)" -ForegroundColor Green
    }
}

# ===== 結算 + 驗證 =====
if (-not $DryRun) {
    Write-Host ""
    Write-Host "===== 驗證 =====" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Service 狀態:"
    Get-Service sshd, ssh-agent -ErrorAction SilentlyContinue | Format-Table Name, Status, StartType -AutoSize

    Write-Host "Port 22:"
    $tnc = Test-NetConnection -ComputerName localhost -Port 22 -WarningAction SilentlyContinue
    if ($tnc.TcpTestSucceeded) {
        Write-Host "  [ok] localhost:22 連通" -ForegroundColor Green
    } else {
        Write-Host "  [warn] localhost:22 不通 (可能 service 啟動慢, 等 5 秒重試)" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "===== OpenSSH 安裝完成 =====" -ForegroundColor Green
    Write-Host ""
    Write-Host "下一步:"
    Write-Host "  1. 重跑 install_offline.ps1, OpenSSH 那步應該變 [skip] 已安裝"
    Write-Host "  2. 從別台主機 ssh u01@<this-host> 測連線"
    Write-Host "  3. 接 startup_sop.md Step 2 建 u01~u04 帳號"
    Write-Host ""
    Write-Host "注意:" -ForegroundColor Yellow
    Write-Host "  - Get-WindowsCapability 仍會顯示 OpenSSH.Server: NotPresent (這是正常的)"
    Write-Host "  - 將來更新 OpenSSH: 抓新版 zip → 停 service → 解壓覆蓋 → 啟動 service"
    Write-Host "  - sshd_config 位置: C:\ProgramData\ssh\sshd_config"
} else {
    Write-Host ""
    Write-Host "===== Dry-run 結束, 沒有實際變動 =====" -ForegroundColor Cyan
}
