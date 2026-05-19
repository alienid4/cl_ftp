<#
.SYNOPSIS
    安裝並啟用 OpenSSH Server (SFTP)。
.DESCRIPTION
    Windows Server 2019/2022 內建 OpenSSH.Server 功能。本腳本安裝、啟動服務、
    設為自動啟動, 並套用範本 sshd_config (放在 config\sshd_config)。
.PARAMETER ConfigTemplate
    sshd_config 範本路徑, 預設 ..\config\sshd_config。
.PARAMETER DryRun
    只列出將執行的動作, 不實際套用。
#>
[CmdletBinding()]
param(
    [string]$ConfigTemplate = (Join-Path $PSScriptRoot '..\config\sshd_config'),
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

Write-Host "`n=== 安裝 OpenSSH Server ===`n" -ForegroundColor Cyan

# 1. 檢查 OpenSSH 是否已裝
#    portable (Win32-OpenSSH zip) 與 FoD 兩種裝法都偵測:
#    - 先看 service sshd 存在 (portable + FoD 共通)
#    - 若無, 再看 WindowsCapability (FoD only)
$sshdSvc = Get-Service -Name sshd -ErrorAction SilentlyContinue
if ($sshdSvc) {
    Write-Host "[skip] OpenSSH 已安裝 (sshd service 存在, $($sshdSvc.Status) / $($sshdSvc.StartType))"
} else {
    $cap = Get-WindowsCapability -Online -Name 'OpenSSH.Server*' -ErrorAction SilentlyContinue
    if ($cap.State -eq 'Installed') {
        Write-Host "[skip] OpenSSH.Server 已安裝 (capability)"
    } elseif ($DryRun) {
        Write-Host "[dry ] Add-WindowsCapability OpenSSH.Server"
    } else {
        # 嘗試 FoD 安裝, 失敗給友善提示 (不 abort, 讓 v1.0.0.5 portable 路線接手)
        try {
            Add-WindowsCapability -Online -Name $cap.Name -ErrorAction Stop
            Write-Host "[ok  ] OpenSSH.Server 安裝完成"
        } catch {
            Write-Host "[fail] FoD 安裝失敗: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "       內網無 FoD source 時改走 portable 路線:" -ForegroundColor Yellow
            Write-Host "         .\scripts\install_openssh_portable.ps1"
            Write-Host "       (詳: patches/v1.0.0.5/PATCH_NOTE.md)"
            exit 1
        }
    }
}

# 2. 啟動 sshd 服務 + 設自動啟動
if ($DryRun) {
    Write-Host "[dry ] Start-Service sshd; Set-Service sshd -StartupType Automatic"
} else {
    Start-Service sshd -ErrorAction SilentlyContinue
    Set-Service -Name sshd -StartupType Automatic
    $svc = Get-Service -Name sshd
    Write-Host "[ok  ] sshd 服務狀態: $($svc.Status), 啟動類型: $($svc.StartType)"
}

# 3. 套用 sshd_config 範本
$targetCfg = 'C:\ProgramData\ssh\sshd_config'
if (-not (Test-Path $ConfigTemplate)) {
    Write-Host "[fail] 找不到 sshd_config 範本: $ConfigTemplate" -ForegroundColor Red
    exit 1
}

if ($DryRun) {
    Write-Host "[dry ] Copy $ConfigTemplate -> $targetCfg (含備份原檔)"
} else {
    if (Test-Path $targetCfg) {
        $backup = "$targetCfg.bak.$(Get-Date -Format yyyyMMdd_HHmmss)"
        Copy-Item $targetCfg $backup -Force
        Write-Host "[ok  ] 原 sshd_config 已備份至 $backup"
    }
    Copy-Item $ConfigTemplate $targetCfg -Force
    Write-Host "[ok  ] 套用 sshd_config 範本"

    # 修正 sshd_config 權限 (OpenSSH 要求 Administrators / SYSTEM 才能讀)
    icacls $targetCfg /inheritance:r | Out-Null
    icacls $targetCfg /grant 'Administrators:F' 'SYSTEM:F' | Out-Null

    # 建立 banner.txt (若不存在), 否則 sshd 啟動會 fail
    $bannerPath = 'C:\ProgramData\ssh\banner.txt'
    if (-not (Test-Path $bannerPath)) {
        $bannerText = @"
=============================================================
  SF File Exchange Server (SFTP)
  Authorized access only. All activities are logged and
  monitored. Unauthorized use is prohibited and may be
  prosecuted under applicable laws.
=============================================================
"@
        Set-Content -Path $bannerPath -Value $bannerText -Encoding ASCII
        icacls $bannerPath /inheritance:r | Out-Null
        icacls $bannerPath /grant 'Administrators:F' 'SYSTEM:F' 'Users:R' | Out-Null
        Write-Host "[ok  ] 建立 banner.txt (預設授權聲明)"
    }

    # Restart 加 try-catch, fail 給友善診斷
    try {
        Restart-Service sshd -ErrorAction Stop
        Write-Host "[ok  ] sshd 重啟"
    } catch {
        Write-Host "[fail] sshd 重啟失敗: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "       排查:" -ForegroundColor Yellow
        Write-Host "       1. 看 Event Log: Get-EventLog -LogName Application -Source OpenSSH -Newest 10"
        Write-Host "       2. 驗 sshd_config 語法: & 'C:\Program Files\OpenSSH\sshd.exe' -t -f '$targetCfg'"
        Write-Host "         (portable 版路徑, FoD 版改 C:\Windows\System32\OpenSSH\sshd.exe)"
        Write-Host "       3. 還原備份: Copy-Item '$backup' '$targetCfg' -Force; Restart-Service sshd"
        Write-Host "       [warn] 繼續執行後續腳本, sshd 之後手動修" -ForegroundColor Yellow
    }
}

# 4. 設防火牆規則 (預設安裝會自動建立, 此處檢查)
$rule = Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue
if ($rule) {
    Write-Host "[ok  ] 防火牆規則 OpenSSH-Server-In-TCP 已存在 ($($rule.Enabled))"
} else {
    if ($DryRun) {
        Write-Host "[dry ] New-NetFirewallRule OpenSSH-Server-In-TCP 22"
    } else {
        New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH SSH Server (sshd)' `
            -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
        Write-Host "[ok  ] 防火牆規則建立"
    }
}

Write-Host "`nOpenSSH 安裝完成。下一步: 04_create_sftp_accounts.ps1" -ForegroundColor Green
Write-Host "提醒: 22 port 來源 IP 白名單將在 05_setup_firewall.ps1 收緊" -ForegroundColor Yellow
