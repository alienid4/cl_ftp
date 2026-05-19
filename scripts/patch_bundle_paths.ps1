<#
.SYNOPSIS
    [Patch] 修正 bundle 路徑 — 把 sf_binaries/ 內的 installers 與 python_wheels
    搬到 deploy/offline/ 根目錄, 讓 install_offline.ps1 找得到。
.DESCRIPTION
    對應 docs/known_issues.md #1 路徑問題。

    背景:
    - fetch_binaries_win11.ps1 抓 binary 到 sf_binaries/installers/
    - 但 install_offline.ps1 預期它們在 deploy/offline/installers/
    - 路徑約定不一致 → 自動修

    這支 patch 會:
    1. 確認當前位置是 deploy/offline/ (或讓使用者指定)
    2. 偵測 sf_binaries/installers 與 sf_binaries/python_wheels
    3. Move 到 deploy/offline/installers 與 deploy/offline/python_wheels
    4. 驗證 install_offline.ps1 預期的位置都有檔
    5. (可選) 清空殼 sf_binaries/

    idempotent: 重跑無害, 已搬過會 skip。
.PARAMETER OfflineDir
    deploy/offline/ 路徑, 預設自動偵測 (this script 在 scripts/ 下, 上一層的 deploy/offline)。
.PARAMETER CleanSfBinaries
    搬完後刪除空殼 sf_binaries/ 目錄。
.PARAMETER DryRun
    只列出將執行的動作, 不實際搬。
.EXAMPLE
    .\patch_bundle_paths.ps1
.EXAMPLE
    .\patch_bundle_paths.ps1 -OfflineDir 'C:\Users\xxx\Desktop\sf_offline_bundle_20260519_0901\deploy\offline'
.EXAMPLE
    .\patch_bundle_paths.ps1 -CleanSfBinaries
#>
[CmdletBinding()]
param(
    [string]$OfflineDir,
    [switch]$CleanSfBinaries,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

Write-Host "`n=== Patch: 修正 bundle 路徑 ===" -ForegroundColor Cyan

# ===== 自動偵測 OfflineDir =====
if (-not $OfflineDir) {
    # 預設: scripts/ 同層級的 deploy/offline/
    $sftpRoot = Split-Path $PSScriptRoot -Parent
    $OfflineDir = Join-Path $sftpRoot 'deploy\offline'
    Write-Host "未指定 -OfflineDir, 自動偵測: $OfflineDir"
}

if (-not (Test-Path $OfflineDir)) {
    Write-Host "[FAIL] OfflineDir 不存在: $OfflineDir" -ForegroundColor Red
    Write-Host "  請用 -OfflineDir 指定正確路徑, 例如:" -ForegroundColor Yellow
    Write-Host "  .\patch_bundle_paths.ps1 -OfflineDir 'C:\Users\<USER>\Desktop\sf_offline_bundle_<TS>\deploy\offline'" -ForegroundColor Yellow
    exit 1
}

# ===== 檢查當前狀態 =====
$sfBinaries = Join-Path $OfflineDir 'sf_binaries'
$targetInstallers = Join-Path $OfflineDir 'installers'
$targetWheels = Join-Path $OfflineDir 'python_wheels'
$sourceInstallers = Join-Path $sfBinaries 'installers'
$sourceWheels = Join-Path $sfBinaries 'python_wheels'

Write-Host ""
Write-Host "===== 當前狀態 =====" -ForegroundColor Yellow
Write-Host "  sf_binaries/ 存在: $(Test-Path $sfBinaries)"
Write-Host "  sf_binaries/installers/ 存在: $(Test-Path $sourceInstallers)"
Write-Host "  sf_binaries/python_wheels/ 存在: $(Test-Path $sourceWheels)"
Write-Host ""
Write-Host "  目標 installers/ 已存在: $(Test-Path $targetInstallers)"
Write-Host "  目標 python_wheels/ 已存在: $(Test-Path $targetWheels)"

# ===== Move installers =====
Write-Host ""
Write-Host "===== Move installers =====" -ForegroundColor Cyan
if (Test-Path $targetInstallers) {
    Write-Host "[skip] $targetInstallers 已存在, 不覆蓋" -ForegroundColor DarkGray
} elseif (Test-Path $sourceInstallers) {
    if ($DryRun) {
        Write-Host "[dry ] Move-Item $sourceInstallers $targetInstallers"
    } else {
        Move-Item $sourceInstallers $targetInstallers
        Write-Host "[ok  ] Moved $sourceInstallers -> $targetInstallers" -ForegroundColor Green
    }
} else {
    Write-Host "[fail] 來源 $sourceInstallers 不存在" -ForegroundColor Red
}

# ===== Move python_wheels =====
Write-Host ""
Write-Host "===== Move python_wheels =====" -ForegroundColor Cyan
if (Test-Path $targetWheels) {
    Write-Host "[skip] $targetWheels 已存在, 不覆蓋" -ForegroundColor DarkGray
} elseif (Test-Path $sourceWheels) {
    if ($DryRun) {
        Write-Host "[dry ] Move-Item $sourceWheels $targetWheels"
    } else {
        Move-Item $sourceWheels $targetWheels
        Write-Host "[ok  ] Moved $sourceWheels -> $targetWheels" -ForegroundColor Green
    }
} else {
    Write-Host "[fail] 來源 $sourceWheels 不存在" -ForegroundColor Red
}

# ===== 驗證 =====
Write-Host ""
Write-Host "===== 驗證 install_offline.ps1 預期位置 =====" -ForegroundColor Cyan
$ok = $true

if (Test-Path $targetInstallers) {
    $installerCount = (Get-ChildItem $targetInstallers -File).Count
    $installerSize = (Get-ChildItem $targetInstallers -Recurse -File | Measure-Object Length -Sum).Sum / 1MB
    Write-Host ("[ok] installers/  {0} 個檔, {1:N1} MB" -f $installerCount, $installerSize) -ForegroundColor Green
} else {
    Write-Host "[FAIL] installers/ 不存在" -ForegroundColor Red
    $ok = $false
}

if (Test-Path $targetWheels) {
    $wheelCount = (Get-ChildItem $targetWheels -Filter '*.whl').Count
    $wheelSize = (Get-ChildItem $targetWheels -Filter '*.whl' | Measure-Object Length -Sum).Sum / 1MB
    Write-Host ("[ok] python_wheels/  {0} 個 wheel, {1:N1} MB" -f $wheelCount, $wheelSize) -ForegroundColor Green
} else {
    Write-Host "[FAIL] python_wheels/ 不存在" -ForegroundColor Red
    $ok = $false
}

# ===== 清空殼 sf_binaries =====
if ($CleanSfBinaries -and (Test-Path $sfBinaries)) {
    Write-Host ""
    Write-Host "===== 清空殼 sf_binaries/ =====" -ForegroundColor Cyan
    $remainingFiles = (Get-ChildItem $sfBinaries -Recurse -File).Count
    if ($remainingFiles -eq 0) {
        if ($DryRun) {
            Write-Host "[dry ] Remove-Item $sfBinaries (空殼)"
        } else {
            Remove-Item $sfBinaries -Recurse -Force
            Write-Host "[ok  ] 空殼 sf_binaries/ 已刪除" -ForegroundColor Green
        }
    } else {
        Write-Host "[skip] sf_binaries/ 內還有 $remainingFiles 個檔 (manifest 等), 不刪" -ForegroundColor Yellow
    }
}

# ===== 結束 =====
Write-Host ""
if ($ok) {
    Write-Host "✓ Patch 完成, 可以跑 install_offline.ps1 了" -ForegroundColor Green
    Write-Host "  cd $OfflineDir"
    Write-Host "  .\install_offline.ps1"
    exit 0
} else {
    Write-Host "✗ Patch 完成但有 FAIL, 不要繼續安裝" -ForegroundColor Red
    exit 1
}
