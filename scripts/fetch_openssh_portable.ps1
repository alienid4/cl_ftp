<#
.SYNOPSIS
    [外網 PC 用] 從 PowerShell Team 官方抓 Win32-OpenSSH portable zip + 算 SHA256, 給 SF 主機帶進去用。
.DESCRIPTION
    此腳本**只在有 Internet 的 PC 跑** (你的工作機 / 申請過外網的機器),
    不需要在 SF 主機跑。

    流程:
    1. 從 https://github.com/PowerShell/Win32-OpenSSH/releases/latest 抓最新版
    2. 算 SHA256 校驗碼
    3. 提示「拷到 USB 後帶到 SF 主機」

    在 SF 主機驗 SHA256, 跑 install_openssh_portable.ps1。
.PARAMETER OutDir
    輸出目錄 (預設: 當前目錄)
.PARAMETER Version
    指定版本, 例: 'v9.5.0.0p1-Beta'。預設 latest。
.EXAMPLE
    .\fetch_openssh_portable.ps1
.EXAMPLE
    .\fetch_openssh_portable.ps1 -OutDir 'D:\sf_install\' -Version 'v9.5.0.0p1-Beta'
.NOTES
    Patch: v1.0.0.6
    對應 issue: docs/dev-log/issues_log.md #010
#>
[CmdletBinding()]
param(
    [string]$OutDir = (Get-Location).Path,
    [string]$Version = 'latest'
)

$ErrorActionPreference = 'Stop'

Write-Host "`n=== Win32-OpenSSH Portable Fetcher (外網 PC 用) ===" -ForegroundColor Cyan
Write-Host "從 PowerShell Team 官方抓最新版 OpenSSH-Win64.zip" -ForegroundColor DarkCyan
Write-Host ""

# 檢查 Internet
Write-Host "[1/4] 確認 Internet..." -ForegroundColor Yellow
try {
    $null = Invoke-WebRequest 'https://api.github.com' -UseBasicParsing -TimeoutSec 5 -Method Head
    Write-Host "[ok] GitHub 可達" -ForegroundColor Green
} catch {
    Write-Host "[FAIL] 無法連到 GitHub. 此腳本必須在有外網的 PC 跑." -ForegroundColor Red
    Write-Host "       若在內網 SF 主機, 改用 install_openssh_portable.ps1 (帶 USB 來的 zip)"
    exit 1
}

# 確認 OutDir
if (-not (Test-Path $OutDir)) {
    New-Item -Path $OutDir -ItemType Directory -Force | Out-Null
}
$OutDir = (Resolve-Path $OutDir).Path

# 取得 release 資訊
Write-Host ""
Write-Host "[2/4] 查 PowerShell Team release 資訊..." -ForegroundColor Yellow
$apiUrl = if ($Version -eq 'latest') {
    'https://api.github.com/repos/PowerShell/Win32-OpenSSH/releases/latest'
} else {
    "https://api.github.com/repos/PowerShell/Win32-OpenSSH/releases/tags/$Version"
}

try {
    $release = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing
} catch {
    Write-Host "[FAIL] 無法查到 release: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$asset = $release.assets | Where-Object { $_.name -eq 'OpenSSH-Win64.zip' } | Select-Object -First 1
if (-not $asset) {
    Write-Host "[FAIL] release $($release.tag_name) 沒有 OpenSSH-Win64.zip" -ForegroundColor Red
    exit 1
}

$sizeMB = '{0:N2}' -f ($asset.size / 1MB)
Write-Host "[ok] Release: $($release.tag_name)"
Write-Host "[ok] Asset: $($asset.name) ($sizeMB MB)"
Write-Host "[ok] URL: $($asset.browser_download_url)"

# 下載
Write-Host ""
Write-Host "[3/4] 下載..." -ForegroundColor Yellow
$outFile = Join-Path $OutDir 'OpenSSH-Win64.zip'

if (Test-Path $outFile) {
    Write-Host "[warn] $outFile 已存在, 跳過下載" -ForegroundColor Yellow
} else {
    try {
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $asset.browser_download_url `
                          -OutFile $outFile `
                          -UseBasicParsing
        Write-Host "[ok] 下載完成: $outFile" -ForegroundColor Green
    } catch {
        Write-Host "[FAIL] 下載失敗: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

# 算 hash
Write-Host ""
Write-Host "[4/4] 算 SHA256..." -ForegroundColor Yellow
$hash = (Get-FileHash $outFile -Algorithm SHA256).Hash
$fileSize = '{0:N2}' -f ((Get-Item $outFile).Length / 1MB)
Write-Host "[ok] SHA256: $hash" -ForegroundColor Green

# 輸出 hash 檔
$hashFile = "$outFile.sha256.txt"
@"
File:    OpenSSH-Win64.zip
Source:  $($asset.browser_download_url)
Release: $($release.tag_name)
Size:    $fileSize MB
SHA256:  $hash
Fetched: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
"@ | Set-Content $hashFile -Encoding UTF8
Write-Host "[ok] Hash 檔: $hashFile"

# 結算
Write-Host ""
Write-Host "===== 完成 =====" -ForegroundColor Cyan
Write-Host ""
Write-Host "輸出:"
Write-Host "  $outFile  ($fileSize MB)"
Write-Host "  $hashFile  (SHA256 校驗檔)"
Write-Host ""
Write-Host "下一步:" -ForegroundColor Yellow
Write-Host "  1. 兩個檔拷到 USB"
Write-Host "  2. 帶到 SF 主機, 放任意目錄 (例: D:\install\)"
Write-Host "  3. 在 SF 主機驗 hash:"
Write-Host "     Get-FileHash 'D:\install\OpenSSH-Win64.zip' -Algorithm SHA256"
Write-Host "     對比: $hash"
Write-Host "  4. 確認一致後跑:"
Write-Host "     .\scripts\install_openssh_portable.ps1"
Write-Host "     (auto-find 會找到 D:\install\OpenSSH-Win64.zip)"
