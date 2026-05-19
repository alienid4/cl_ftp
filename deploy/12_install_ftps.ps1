<#
.SYNOPSIS
    安裝 IIS FTP Server 並設定 FTPS (FTP over TLS), 對齊主管圖「方案二: FTPS」備案。
.DESCRIPTION
    安裝 Web-Ftp-Server 角色, 建立 FTPS Site 指向 D:\DataExchange\,
    啟用 TLS 加密 + Passive Port Range 50000-50100。
    **預設停用 service**, 真有需要才啟動 (主管圖備註: 若既有系統不支援 SFTP 才用 FTPS)。
.PARAMETER CertThumbprint
    TLS 憑證 thumbprint (從 Cert:\LocalMachine\My 取得)。
.PARAMETER HostName
    FTPS 綁定 host header。
.PARAMETER PassivePortLow
    Passive Data Port 起始, 預設 50000。
.PARAMETER PassivePortHigh
    Passive Data Port 結束, 預設 50100 (共 101 port)。
.PARAMETER DryRun
    只列出將執行的動作, 不實際套用。
#>
[CmdletBinding()]
param(
    [string]$CertThumbprint,
    [string]$HostName = 'sf-ftps.corp.local',
    [int]$PassivePortLow = 50000,
    [int]$PassivePortHigh = 50100,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

Write-Host "`n=== 安裝 IIS FTP Server (FTPS 備案) ===`n" -ForegroundColor Cyan

# 1. 安裝 FTP Server 角色
$ftpFeature = Get-WindowsFeature -Name Web-Ftp-Server
if ($ftpFeature.InstallState -ne 'Installed') {
    if ($DryRun) {
        Write-Host "[dry ] Install-WindowsFeature Web-Ftp-Server"
    } else {
        Install-WindowsFeature -Name Web-Ftp-Server -IncludeAllSubFeature | Out-Null
        Write-Host "[ok  ] FTP Server 角色已安裝"
    }
} else {
    Write-Host "[skip] FTP Server 角色已安裝"
}

Import-Module WebAdministration -ErrorAction SilentlyContinue

# 2. 建立 FTP Site
$siteName = 'FileExchangeFTPS'
$site = Get-Website -Name $siteName -ErrorAction SilentlyContinue
if ($site) {
    Write-Host "[skip] FTP Site $siteName 已存在"
} else {
    if ($DryRun) {
        Write-Host "[dry ] New FTP Site $siteName -> D:\DataExchange"
    } else {
        New-WebFtpSite -Name $siteName -Port 21 -PhysicalPath 'D:\DataExchange' -Force | Out-Null
        Write-Host "[ok  ] 建立 FTPS Site $siteName"
    }
}

# 3. 設定 TLS (Require SSL)
if (-not $DryRun) {
    if (-not $CertThumbprint) {
        Write-Host "[warn] 未提供 -CertThumbprint, TLS 暫時不綁憑證 (後續手動設)" -ForegroundColor Yellow
    } else {
        Set-ItemProperty "IIS:\Sites\$siteName" -Name ftpServer.security.ssl.serverCertHash -Value $CertThumbprint
        Set-ItemProperty "IIS:\Sites\$siteName" -Name ftpServer.security.ssl.controlChannelPolicy -Value 'SslRequire'
        Set-ItemProperty "IIS:\Sites\$siteName" -Name ftpServer.security.ssl.dataChannelPolicy -Value 'SslRequire'
        Write-Host "[ok  ] TLS Require 設定, 憑證 thumbprint=$CertThumbprint"
    }
}

# 4. 設定 Passive Port Range
if (-not $DryRun) {
    Set-WebConfigurationProperty -Filter '/system.ftpServer/firewallSupport' `
        -Name 'lowDataChannelPort' -Value $PassivePortLow -PSPath 'IIS:\'
    Set-WebConfigurationProperty -Filter '/system.ftpServer/firewallSupport' `
        -Name 'highDataChannelPort' -Value $PassivePortHigh -PSPath 'IIS:\'
    Write-Host "[ok  ] Passive Port Range: $PassivePortLow-$PassivePortHigh"
}

# 5. 認證: 使用 Windows Basic (給 u0X 業務代號帳號用)
if (-not $DryRun) {
    Set-ItemProperty "IIS:\Sites\$siteName" -Name ftpServer.security.authentication.basicAuthentication.enabled -Value $true
    Set-ItemProperty "IIS:\Sites\$siteName" -Name ftpServer.security.authentication.anonymousAuthentication.enabled -Value $false
    Write-Host "[ok  ] Basic 認證啟用, Anonymous 停用"

    # 授權 sftp_users 群組
    Add-WebConfiguration -Filter "/system.ftpServer/security/authorization" `
        -Value @{accessType='Allow'; users=''; roles="sftp_users"; permissions='Read,Write'} `
        -PSPath "IIS:\" -Location $siteName
    Write-Host "[ok  ] 授權 sftp_users 群組 Read+Write"
}

# 6. 防火牆規則 (Passive Port Range)
if ($DryRun) {
    Write-Host "[dry ] New-NetFirewallRule FTPS Passive Range $PassivePortLow-$PassivePortHigh"
} else {
    $existing = Get-NetFirewallRule -Name 'FX-FTPS-Passive-In' -ErrorAction SilentlyContinue
    if ($existing) { Remove-NetFirewallRule -Name 'FX-FTPS-Passive-In' }

    New-NetFirewallRule -Name 'FX-FTPS-Passive-In' -DisplayName 'FileExchange FTPS Passive Range' `
        -Direction Inbound -Protocol TCP -LocalPort "$PassivePortLow-$PassivePortHigh" `
        -Action Allow -Enabled True -RemoteAddress '10.0.0.0/8' | Out-Null
    Write-Host "[ok  ] 防火牆 FTPS Passive Range 規則建立"
}

# 7. **預設停用 service** (依主管圖備註, 真有需要才開)
if (-not $DryRun) {
    Stop-Service -Name 'FTPSVC' -ErrorAction SilentlyContinue
    Set-Service -Name 'FTPSVC' -StartupType Manual
    Write-Host "[ok  ] FTPSVC 服務已停止 + 設為 Manual 啟動 (預設停用)" -ForegroundColor Yellow
}

Write-Host "`nFTPS 備案已準備, 服務預設停用。" -ForegroundColor Green
Write-Host "需要啟用時: Start-Service FTPSVC; Set-Service FTPSVC -StartupType Automatic" -ForegroundColor Yellow
