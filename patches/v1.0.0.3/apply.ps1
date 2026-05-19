<#
.SYNOPSIS
    [Patch v1.0.0.3] 一鍵套用 — install_offline.ps1 完全 idempotent + 容錯。
.DESCRIPTION
    覆蓋舊版 install_offline.ps1, 使其:
    1. 每個 step 檢查「已裝就 skip」
    2. 單步失敗不 abort, 結尾顯示 summary
    3. OpenSSH 失敗給明確 fallback 指引

    對應 PATCH_NOTE.md。
.PARAMETER ProjectRoot
    SF 專案根目錄, 預設自動偵測。
.PARAMETER DryRun
    只列出將執行的動作。
.EXAMPLE
    .\apply.ps1
.EXAMPLE
    .\apply.ps1 -ProjectRoot 'C:\ClaudeHome\SFTP'
#>
[CmdletBinding()]
param(
    [string]$ProjectRoot,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

Write-Host "`n=== Apply Patch v1.0.0.3 ===" -ForegroundColor Cyan
Write-Host "對應問題: install_offline.ps1 完全 idempotent + 容錯 + OpenSSH FoD 失敗指引" -ForegroundColor Yellow
Write-Host ""

# ===== 1. 偵測 ProjectRoot =====
if (-not $ProjectRoot) {
    $ProjectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Write-Host "[auto] ProjectRoot = $ProjectRoot"
}

if (-not (Test-Path $ProjectRoot)) {
    Write-Host "[FAIL] ProjectRoot 不存在: $ProjectRoot" -ForegroundColor Red
    exit 1
}

# 驗證是 SF 專案
$markers = @('README.md', 'deploy', 'scripts')
foreach ($m in $markers) {
    if (-not (Test-Path (Join-Path $ProjectRoot $m))) {
        Write-Host "[FAIL] $ProjectRoot 似乎不是 SF 專案根 (缺 $m)" -ForegroundColor Red
        exit 1
    }
}
Write-Host "[ok] ProjectRoot 驗證通過"

# ===== 2. 拷貝 files/ =====
$filesDir = Join-Path $PSScriptRoot 'files'
if (-not (Test-Path $filesDir)) {
    Write-Host "[FAIL] 找不到 files/ 目錄: $filesDir" -ForegroundColor Red
    exit 1
}

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$copied = 0
$skipped = 0
$backedUp = 0

Write-Host ""
Write-Host "===== 套用檔案 =====" -ForegroundColor Cyan
Get-ChildItem $filesDir -Recurse -File | ForEach-Object {
    $relPath = $_.FullName.Substring($filesDir.Length + 1)
    $srcFile = $_.FullName
    $dstFile = Join-Path $ProjectRoot $relPath
    $dstDir = Split-Path $dstFile -Parent

    Write-Host ""
    Write-Host "[file] $relPath"

    if (-not (Test-Path $dstDir)) {
        if ($DryRun) {
            Write-Host "  [dry] mkdir $dstDir"
        } else {
            New-Item -Path $dstDir -ItemType Directory -Force | Out-Null
        }
    }

    if (Test-Path $dstFile) {
        $srcHash = (Get-FileHash $srcFile -Algorithm SHA256).Hash
        $dstHash = (Get-FileHash $dstFile -Algorithm SHA256).Hash
        if ($srcHash -eq $dstHash) {
            Write-Host "  [skip] 已是修正版 (SHA256 一致)" -ForegroundColor DarkGray
            $skipped++
            return
        }

        $bakFile = "$dstFile.bak.$timestamp"
        if ($DryRun) {
            Write-Host "  [dry] backup $dstFile -> $bakFile"
        } else {
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
Write-Host "  覆蓋:   $copied"
Write-Host "  Skip:   $skipped (檔案已是最新)"
Write-Host "  備份:   $backedUp"
Write-Host ""

if ($DryRun) {
    Write-Host "[dry-run] 預演完畢, 沒實際變動" -ForegroundColor Yellow
    Write-Host "正式跑: .\apply.ps1" -ForegroundColor Yellow
} else {
    Write-Host "✓ Patch v1.0.0.3 套用完成" -ForegroundColor Green
    Write-Host ""
    Write-Host "下一步: 重跑 install_offline.ps1 (idempotent, 已裝 skip)" -ForegroundColor Cyan
    Write-Host "  cd $ProjectRoot\deploy\offline"
    Write-Host "  .\install_offline.ps1"
}
