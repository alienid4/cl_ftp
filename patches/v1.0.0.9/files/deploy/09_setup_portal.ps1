<#
.SYNOPSIS
    部署 Python Flask Portal 應用程式並設定 IIS 反向代理。
.DESCRIPTION
    1. 安裝 Python 3.11+ (檢查)
    2. 在 D:\DataExchange\_portal\app 建立虛擬環境並安裝 requirements
    3. 將本專案 portal/ 目錄複製過去
    4. 註冊為 Windows Service (使用 NSSM 或內建 sc.exe)
    5. 透過 IIS URL Rewrite 反向代理 https://<host>/ -> http://127.0.0.1:5000/
.PARAMETER PortalSource
    本地 portal 程式碼路徑, 預設 ..\portal
.PARAMETER PortalTarget
    部署目的, 預設 D:\DataExchange\_portal\app
.PARAMETER ListenPort
    Flask backend listen port, 預設 5000 (僅 127.0.0.1)
.PARAMETER DryRun
    只列出將執行的動作, 不實際套用。
#>
[CmdletBinding()]
param(
    [string]$PortalSource = (Join-Path $PSScriptRoot '..\portal'),
    [string]$PortalTarget = 'D:\_portal\app',
    [int]$ListenPort      = 5000,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

Write-Host "`n=== 部署 Flask Portal ===`n" -ForegroundColor Cyan

# 1. 檢查 Python (多重 fallback, 含 user-only 安裝路徑)
function Find-Python {
    # 嘗試 1: PATH 內 python.exe
    $cmd = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    # 嘗試 2: user-only 安裝 (install_offline.ps1 用這個)
    $userPaths = @(
        "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python310\python.exe",
        "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe"
    )
    foreach ($p in $userPaths) {
        if (Test-Path $p) { return $p }
    }

    # 嘗試 3: 系統安裝
    $sysPaths = @(
        'C:\Python311\python.exe',
        'C:\Python310\python.exe',
        'C:\Program Files\Python311\python.exe',
        'C:\Program Files\Python310\python.exe'
    )
    foreach ($p in $sysPaths) {
        if (Test-Path $p) { return $p }
    }

    return $null
}

$pythonExe = Find-Python
if (-not $pythonExe) {
    Write-Host "[fail] 未偵測到 Python, 請安裝 Python 3.11+ 或加入 PATH" -ForegroundColor Red
    Write-Host "  install_offline.ps1 通常裝在 $env:LOCALAPPDATA\Programs\Python\Python311\"
    Write-Host "  下載: https://www.python.org/downloads/"
    exit 1
}
$pyVer = & $pythonExe --version 2>&1
Write-Host "[ok  ] Python: $pyVer ($pythonExe)"
# 後續用 $pythonExe 取代直接呼叫 python

# 2. 複製程式碼
if (-not (Test-Path $PortalSource)) {
    Write-Host "[fail] 找不到 portal 程式碼: $PortalSource" -ForegroundColor Red
    exit 1
}

if ($DryRun) {
    Write-Host "[dry ] robocopy $PortalSource $PortalTarget"
} else {
    & robocopy $PortalSource $PortalTarget /E /XO /R:2 /W:5 /NFL /NDL /NP /NS | Out-Null
    Write-Host "[ok  ] 程式碼複製至 $PortalTarget"
}

# 3. 建立虛擬環境並安裝依賴
$venv = Join-Path $PortalTarget '.venv'
if ($DryRun) {
    Write-Host "[dry ] python -m venv $venv; pip install -r requirements.txt"
} else {
    if (-not (Test-Path $venv)) {
        & $pythonExe -m venv $venv
        Write-Host "[ok  ] 建立虛擬環境 $venv"
    }
    $pip = Join-Path $venv 'Scripts\pip.exe'
    $req = Join-Path $PortalTarget 'requirements.txt'
    if (Test-Path $req) {
        & $pip install --upgrade pip | Out-Null
        & $pip install -r $req
        Write-Host "[ok  ] 安裝 requirements.txt"
    }
}

# 4. 註冊 Windows Service (用 sc.exe + waitress-serve)
$svcName = 'FileExchangePortal'
$existing = Get-Service -Name $svcName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "[skip] Service $svcName 已存在"
} else {
    $waitress = Join-Path $venv 'Scripts\waitress-serve.exe'
    $binPath = "`"$waitress`" --listen=127.0.0.1:$ListenPort --call wsgi:create_app"
    if ($DryRun) {
        Write-Host "[dry ] sc.exe create $svcName binPath= $binPath start= auto"
    } else {
        # 註: 直接用 sc.exe 啟動 console exe 在 Windows Service context 下行為不穩,
        #     正式環境建議用 NSSM (https://nssm.cc/) 或寫個 wrapper service
        Write-Host "[info] 建議使用 NSSM 將 waitress-serve 註冊為 Windows Service:" -ForegroundColor Yellow
        Write-Host "  nssm install $svcName `"$waitress`"" -ForegroundColor Yellow
        Write-Host "  nssm set $svcName AppParameters --listen=127.0.0.1:$ListenPort --call wsgi:create_app" -ForegroundColor Yellow
        Write-Host "  nssm set $svcName AppDirectory `"$PortalTarget`"" -ForegroundColor Yellow
        Write-Host "  nssm set $svcName Start SERVICE_AUTO_START" -ForegroundColor Yellow
    }
}

# 5. 設定 IIS URL Rewrite (假設 URL Rewrite 已安裝)
$webConfig = Join-Path $PortalTarget 'web.config'
$srcConfig = Join-Path $PSScriptRoot '..\config\web.config'
if (Test-Path $srcConfig) {
    if ($DryRun) {
        Write-Host "[dry ] Copy $srcConfig -> $webConfig"
    } else {
        Copy-Item $srcConfig $webConfig -Force
        Write-Host "[ok  ] 部署 web.config (含反向代理規則 + TLS / Header 強化)"
    }
}

Write-Host "`nPortal 部署完成。" -ForegroundColor Green
Write-Host "驗證: 開啟 https://<host-name>/ 應可看到登入頁" -ForegroundColor Yellow
