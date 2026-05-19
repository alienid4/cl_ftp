<#
.SYNOPSIS
    安裝 IIS 與 Portal 所需模組, 建立 IIS Site 與 App Pool。
.DESCRIPTION
    安裝 Web-Server 角色與必要模組 (URL Rewrite / HTTP Redirect / Static Content),
    建立應用程式池 FileExchangePortal (NoManagedCode), 並建立 HTTPS Site
    指向 D:\DataExchange\_portal\app, 綁定憑證 thumbprint。

    本腳本不負責下載與安裝 URL Rewrite 模組 (需另外從 Microsoft 取得), 會提示。
.PARAMETER SiteName
    IIS Site 名稱, 預設 FileExchangePortal。
.PARAMETER AppPoolName
    App Pool 名稱, 預設 FileExchangePortal。
.PARAMETER PhysicalPath
    Site 實體路徑, 預設 D:\DataExchange\_portal\app。
.PARAMETER CertThumbprint
    SSL 憑證 thumbprint (大寫無空白)。從 cert:\LocalMachine\My 取得。
.PARAMETER HostName
    HTTPS 綁定 host header, 例: fileexchange.corp.local
.PARAMETER DryRun
    只列出將執行的動作, 不實際套用。
#>
[CmdletBinding()]
param(
    [string]$SiteName     = 'FileExchangePortal',
    [string]$AppPoolName  = 'FileExchangePortal',
    [string]$PhysicalPath = 'D:\DataExchange\_portal\app',
    [string]$CertThumbprint,
    [string]$HostName     = 'fileexchange.corp.local',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

Write-Host "`n=== 安裝 IIS 與部署 Portal Site ===`n" -ForegroundColor Cyan

# 1. 安裝 IIS 角色與模組
$features = @(
    'Web-Server',
    'Web-WebServer',
    'Web-Common-Http',
    'Web-Static-Content',
    'Web-Default-Doc',
    'Web-Http-Errors',
    'Web-Http-Logging',
    'Web-Custom-Logging',
    'Web-Request-Monitor',
    'Web-Security',
    'Web-Filtering',
    'Web-Performance',
    'Web-Mgmt-Console'
)

foreach ($f in $features) {
    $st = Get-WindowsFeature -Name $f
    if ($st.InstallState -eq 'Installed') {
        Write-Host "[skip] $f"
    } else {
        if ($DryRun) {
            Write-Host "[dry ] Install-WindowsFeature $f"
        } else {
            Install-WindowsFeature -Name $f | Out-Null
            Write-Host "[ok  ] 安裝 $f"
        }
    }
}

# 2. 載入 IIS module
Import-Module WebAdministration -ErrorAction SilentlyContinue

# 3. 建立 App Pool
$existingPool = Get-Item "IIS:\AppPools\$AppPoolName" -ErrorAction SilentlyContinue
if ($existingPool) {
    Write-Host "[skip] App Pool $AppPoolName 已存在"
} else {
    if ($DryRun) {
        Write-Host "[dry ] New-WebAppPool $AppPoolName (NoManagedCode)"
    } else {
        New-WebAppPool -Name $AppPoolName | Out-Null
        Set-ItemProperty "IIS:\AppPools\$AppPoolName" -Name managedRuntimeVersion -Value ''
        Set-ItemProperty "IIS:\AppPools\$AppPoolName" -Name processModel.identityType -Value ApplicationPoolIdentity
        Write-Host "[ok  ] 建立 App Pool $AppPoolName"
    }
}

# 4. 建立 Site
if (-not (Test-Path $PhysicalPath)) {
    New-Item -Path $PhysicalPath -ItemType Directory -Force | Out-Null
}

$site = Get-Website -Name $SiteName -ErrorAction SilentlyContinue
if ($site) {
    Write-Host "[skip] Site $SiteName 已存在"
} else {
    if ($DryRun) {
        Write-Host "[dry ] New-Website $SiteName -> $PhysicalPath (HTTPS 443, host=$HostName)"
    } else {
        if (-not $CertThumbprint) {
            Write-Host "[fail] 未提供 -CertThumbprint, 無法建立 HTTPS 綁定" -ForegroundColor Red
            Write-Host "請至 Cert:\LocalMachine\My 安裝憑證後, 用 thumbprint 重跑此腳本。"
            exit 1
        }

        New-Website -Name $SiteName -PhysicalPath $PhysicalPath -ApplicationPool $AppPoolName `
            -HostHeader $HostName -Port 443 -Ssl | Out-Null

        # 綁憑證
        $binding = Get-WebBinding -Name $SiteName -Protocol https
        $binding.AddSslCertificate($CertThumbprint, 'My')

        Write-Host "[ok  ] 建立 Site $SiteName, 綁定 HTTPS 443 cert=$CertThumbprint"
    }
}

# 5. 移除 Default Web Site (避免佔用 80/443)
$default = Get-Website -Name 'Default Web Site' -ErrorAction SilentlyContinue
if ($default -and $default.State -eq 'Started') {
    if ($DryRun) {
        Write-Host "[dry ] Stop Default Web Site"
    } else {
        Stop-Website -Name 'Default Web Site'
        Write-Host "[ok  ] 停止 Default Web Site"
    }
}

# 6. 提示: URL Rewrite (Portal 反向代理到 Python 後端時需要)
Write-Host ""
Write-Host "提醒: 若 Portal 使用 Python Flask + IIS 反向代理, 需另外安裝 URL Rewrite 與 ARR 模組:" -ForegroundColor Yellow
Write-Host "  https://www.iis.net/downloads/microsoft/url-rewrite" -ForegroundColor Yellow
Write-Host "  https://www.iis.net/downloads/microsoft/application-request-routing" -ForegroundColor Yellow

Write-Host "`nIIS 安裝完成。下一步: 07_setup_gpo_policy.ps1" -ForegroundColor Green
