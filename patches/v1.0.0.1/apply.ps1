<#
.SYNOPSIS
    [Patch v1.0.0.1] 一鍵套用 — 修 install_offline.ps1 找不到 installers 路徑問題。
.DESCRIPTION
    對應 PATCH_NOTE.md。會做兩件事:

    1. 把 files/ 目錄內的修正檔覆蓋到 SF 專案根目錄 (備份原檔成 .bak.<時間戳>)
    2. (可選) 跑 patch_bundle_paths.ps1 立刻把 sf_binaries/installers 搬正確位置

    idempotent: 重跑無害, 已套用會 skip。
.PARAMETER ProjectRoot
    SF 專案根目錄, 預設自動偵測 (apply.ps1 在 patches/v1.0.0.1/, 上兩層即 SF root)。
.PARAMETER RunPathFix
    套用 patch 後立刻跑 patch_bundle_paths.ps1 修路徑 (預設啟用)。
.PARAMETER DryRun
    只列出將執行的動作。
.EXAMPLE
    .\apply.ps1
.EXAMPLE
    .\apply.ps1 -ProjectRoot 'C:\ClaudeHome\SFTP'
.EXAMPLE
    .\apply.ps1 -DryRun
#>
[CmdletBinding()]
param(
    [string]$ProjectRoot,
    [switch]$DryRun,
    [bool]$RunPathFix = $true
)

$ErrorActionPreference = 'Stop'

Write-Host "`n=== Apply Patch v1.0.0.1 ===" -ForegroundColor Cyan
Write-Host "對應問題: install_offline.ps1 找不到 installers 路徑" -ForegroundColor Yellow
Write-Host ""

# ===== 1. 偵測 ProjectRoot =====
if (-not $ProjectRoot) {
    # apply.ps1 在 patches/v1.0.0.1/, 上兩層是 SF root
    $ProjectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Write-Host "[auto] ProjectRoot = $ProjectRoot"
}

if (-not (Test-Path $ProjectRoot)) {
    Write-Host "[FAIL] ProjectRoot 不存在: $ProjectRoot" -ForegroundColor Red
    exit 1
}

# 驗證是 SF 專案 (檢查關鍵檔)
$markers = @('README.md', 'deploy', 'scripts')
foreach ($m in $markers) {
    if (-not (Test-Path (Join-Path $ProjectRoot $m))) {
        Write-Host "[FAIL] $ProjectRoot 似乎不是 SF 專案根 (缺 $m)" -ForegroundColor Red
        exit 1
    }
}
Write-Host "[ok] ProjectRoot 驗證通過"

# ===== 2. 拷貝 files/ 內容 =====
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

    # 確保目的目錄存在
    if (-not (Test-Path $dstDir)) {
        if ($DryRun) {
            Write-Host "  [dry] mkdir $dstDir"
        } else {
            New-Item -Path $dstDir -ItemType Directory -Force | Out-Null
        }
    }

    # 如果目標已存在, 先比對 hash
    if (Test-Path $dstFile) {
        $srcHash = (Get-FileHash $srcFile -Algorithm SHA256).Hash
        $dstHash = (Get-FileHash $dstFile -Algorithm SHA256).Hash
        if ($srcHash -eq $dstHash) {
            Write-Host "  [skip] 已是修正版 (SHA256 一致)" -ForegroundColor DarkGray
            $skipped++
            return
        }

        # 備份原檔
        $bakFile = "$dstFile.bak.$timestamp"
        if ($DryRun) {
            Write-Host "  [dry] backup $dstFile -> $bakFile"
        } else {
            Copy-Item $dstFile $bakFile
            Write-Host "  [backup] $bakFile" -ForegroundColor Yellow
            $backedUp++
        }
    }

    # 拷貝
    if ($DryRun) {
        Write-Host "  [dry] copy $srcFile -> $dstFile"
    } else {
        Copy-Item $srcFile $dstFile -Force
        Write-Host "  [ok] 已套用" -ForegroundColor Green
        $copied++
    }
}

# ===== 3. 摘要 =====
Write-Host ""
Write-Host "===== 套用結果 =====" -ForegroundColor Cyan
Write-Host "  覆蓋:   $copied"
Write-Host "  Skip:   $skipped (檔案已是最新)"
Write-Host "  備份:   $backedUp"

# ===== 4. 跑 patch_bundle_paths.ps1 (可選) =====
if ($RunPathFix -and -not $DryRun) {
    Write-Host ""
    Write-Host "===== 修 sf_binaries 路徑 =====" -ForegroundColor Cyan
    $pathFix = Join-Path $ProjectRoot 'scripts\patch_bundle_paths.ps1'
    if (Test-Path $pathFix) {
        & $pathFix
    } else {
        Write-Host "[skip] $pathFix 不存在 (patch 尚未套用?)" -ForegroundColor Yellow
    }
}

# ===== 5. 結束 =====
Write-Host ""
if ($DryRun) {
    Write-Host "[dry-run] 預演完畢, 沒實際變動" -ForegroundColor Yellow
    Write-Host "正式跑: .\apply.ps1" -ForegroundColor Yellow
} else {
    Write-Host "✓ Patch v1.0.0.1 套用完成" -ForegroundColor Green
    Write-Host ""
    Write-Host "下一步: 重新跑 install_offline.ps1" -ForegroundColor Cyan
    Write-Host "  cd $ProjectRoot\deploy\offline"
    Write-Host "  .\install_offline.ps1"
}
