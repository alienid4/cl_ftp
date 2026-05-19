<#
.SYNOPSIS
    設定 Windows 防火牆入規則 (含來源 IP 白名單)。
.DESCRIPTION
    建立規則:
    - TCP 443 (HTTPS Portal) -> 來源: 內部使用者網段
    - TCP 22  (SFTP)         -> 來源: 授權系統 IP 白名單
    - TCP 3389 (RDP 維運)    -> 來源: 跳板機 IP 白名單
    其餘預設 deny。
.PARAMETER PortalSources
    Portal HTTPS 來源網段 (CIDR), 例: '10.0.0.0/8','172.16.0.0/12'
.PARAMETER SftpSources
    SFTP 來源 IP / 網段
.PARAMETER RdpSources
    RDP 來源 IP (跳板機), 例: '10.1.2.3'
.PARAMETER DryRun
    只列出將執行的動作, 不實際套用。
#>
[CmdletBinding()]
param(
    [string[]]$PortalSources = @('10.0.0.0/8'),
    [string[]]$SftpSources   = @('10.0.0.0/8'),
    [string[]]$RdpSources    = @('10.0.0.0/8'),
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Set-FwRule {
    param(
        [string]$Name,
        [string]$DisplayName,
        [int]$Port,
        [string[]]$RemoteAddress
    )
    $existing = Get-NetFirewallRule -Name $Name -ErrorAction SilentlyContinue
    if ($DryRun) {
        Write-Host "[dry ] $Name : TCP $Port from [$($RemoteAddress -join ', ')]"
        return
    }
    if ($existing) {
        Remove-NetFirewallRule -Name $Name
    }
    New-NetFirewallRule -Name $Name -DisplayName $DisplayName `
        -Direction Inbound -Protocol TCP -LocalPort $Port -Action Allow `
        -RemoteAddress $RemoteAddress -Enabled True -Profile Any | Out-Null
    Write-Host "[ok  ] $Name : TCP $Port from [$($RemoteAddress -join ', ')]"
}

Write-Host "`n=== 設定防火牆規則 ===`n" -ForegroundColor Cyan

Set-FwRule -Name 'FX-HTTPS-443-In' -DisplayName 'FileExchange Portal HTTPS' `
    -Port 443 -RemoteAddress $PortalSources

Set-FwRule -Name 'FX-SFTP-22-In' -DisplayName 'FileExchange SFTP (Whitelist)' `
    -Port 22 -RemoteAddress $SftpSources

Set-FwRule -Name 'FX-RDP-3389-In' -DisplayName 'FileExchange RDP (Bastion only)' `
    -Port 3389 -RemoteAddress $RdpSources

# 停用 OpenSSH 預設規則 (沒限制來源), 改用上面收緊版
$default = Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue
if ($default) {
    if ($DryRun) {
        Write-Host "[dry ] Disable OpenSSH-Server-In-TCP (預設不限制來源, 改用 FX-SFTP-22-In)"
    } else {
        Disable-NetFirewallRule -Name 'OpenSSH-Server-In-TCP'
        Write-Host "[ok  ] 停用預設 OpenSSH-Server-In-TCP (改用 FX-SFTP-22-In)"
    }
}

Write-Host "`n防火牆規則設定完成。" -ForegroundColor Green
Write-Host "請依公司實際內部網段調整 -PortalSources / -SftpSources / -RdpSources" -ForegroundColor Yellow
