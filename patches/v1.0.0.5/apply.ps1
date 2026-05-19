<#
.SYNOPSIS
    [Patch v1.0.0.5] 一鍵套用 — 新增 install_openssh_portable.ps1 helper。
.DESCRIPTION
    把 install_openssh_portable.ps1 拷到 scripts/。
    對應 PATCH_NOTE.md (用 Win32-OpenSSH portable zip 裝, 不需 FoD / ISO)。
#>
[CmdletBinding()]
param(
    [string]$ProjectRoot,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

Write-Host "`n=== Apply Patch v1.0.0.5 ===" -ForegroundColor Cyan
Write-Host "新增 install_openssh_portable.ps1 (Win32-OpenSSH portable, 不需 FoD)" -ForegroundColor Yellow

if (-not $ProjectRoot) {
    $ProjectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Write-Host "[auto] ProjectRoot = $ProjectRoot"
}

if (-not (Test-Path $ProjectRoot)) {
    Write-Host "[FAIL] ProjectRoot 不存在: $ProjectRoot" -ForegroundColor Red
    exit 1
}

$filesDir = Join-Path $PSScriptRoot 'files'
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$copied = 0; $skipped = 0; $backedUp = 0

Get-ChildItem $filesDir -Recurse -File | ForEach-Object {
    $relPath = $_.FullName.Substring($filesDir.Length + 1)
    $srcFile = $_.FullName
    $dstFile = Join-Path $ProjectRoot $relPath
    $dstDir = Split-Path $dstFile -Parent

    Write-Host ""
    Write-Host "[file] $relPath"

    if (-not (Test-Path $dstDir) -and -not $DryRun) {
        New-Item -Path $dstDir -ItemType Directory -Force | Out-Null
    }

    if (Test-Path $dstFile) {
        $srcHash = (Get-FileHash $srcFile -Algorithm SHA256).Hash
        $dstHash = (Get-FileHash $dstFile -Algorithm SHA256).Hash
        if ($srcHash -eq $dstHash) {
            Write-Host "  [skip] 已是最新 (SHA256 一致)" -ForegroundColor DarkGray
            $skipped++
            return
        }
        if (-not $DryRun) {
            $bakFile = "$dstFile.bak.$timestamp"
            Copy-Item $dstFile $bakFile
            Write-Host "  [backup] $bakFile" -ForegroundColor Yellow
            $backedUp++
        }
    }

    if ($DryRun) {
        Write-Host "  [dry] copy $srcFile -> $dstFile"
    } else {
        Copy-Item $srcFile $dstFile -Force
        Write-Host "  [ok] 已套用" -ForegroundColor Green
        $copied++
    }
}

Write-Host ""
Write-Host "===== 套用結果 =====" -ForegroundColor Cyan
Write-Host "  覆蓋: $copied / Skip: $skipped / 備份: $backedUp"
Write-Host ""

if (-not $DryRun) {
    Write-Host "✓ Patch v1.0.0.5 套用完成" -ForegroundColor Green
    Write-Host ""
    Write-Host "下一步: 取得 OpenSSH-Win64.zip 後跑:" -ForegroundColor Cyan
    Write-Host "  1. 外網抓 https://github.com/PowerShell/Win32-OpenSSH/releases/latest"
    Write-Host "     下載 OpenSSH-Win64.zip (約 5 MB)"
    Write-Host "  2. USB 拷到 SF 主機 (例如 D:\OpenSSH-Win64.zip)"
    Write-Host "  3. 跑:"
    Write-Host "       cd $ProjectRoot"
    Write-Host "       .\scripts\install_openssh_portable.ps1 -ZipPath 'D:\OpenSSH-Win64.zip'"
    Write-Host ""
    Write-Host "提示: 此 patch 替代 v1.0.0.4 ISO 路線, 推薦使用" -ForegroundColor DarkCyan
}
