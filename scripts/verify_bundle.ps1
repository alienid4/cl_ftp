<#
.SYNOPSIS
    [SF 主機] 驗證從 USB / share 解壓的 bundle 完整性。
.DESCRIPTION
    比對每個檔案的 SHA256 與 manifest.json, 確保:
    - 沒缺檔
    - 沒檔案被破壞 / 篡改
    - bundle 結構符合預期

    跑 install_offline.ps1 之前**強烈建議**先跑這支。
.PARAMETER BundleRoot
    bundle 解壓的根目錄, 預設當前目錄 (應該是 C:\ClaudeHome\SFTP\)。
.PARAMETER QuickMode
    只驗證關鍵檔案 (installers/*, 跳過 wheels 與 docs)。
.EXAMPLE
    .\verify_bundle.ps1
.EXAMPLE
    .\verify_bundle.ps1 -BundleRoot C:\ClaudeHome\SFTP -QuickMode
#>
[CmdletBinding()]
param(
    [string]$BundleRoot = (Split-Path $PSScriptRoot -Parent),
    [switch]$QuickMode
)

$ErrorActionPreference = 'Continue'

Write-Host "`n=== Bundle 完整性驗證 ===" -ForegroundColor Cyan
Write-Host "Bundle 根目錄: $BundleRoot"
Write-Host "模式: $(if ($QuickMode) { 'Quick (只查 installers)' } else { 'Full' })`n"

# ===== 1. 找 manifest =====
$manifestPath = Join-Path $BundleRoot 'manifest.json'
if (-not (Test-Path $manifestPath)) {
    Write-Host "[FAIL] 找不到 manifest.json" -ForegroundColor Red
    Write-Host "  bundle 可能不完整或解壓位置錯誤" -ForegroundColor Yellow
    Write-Host "  預期路徑: $manifestPath" -ForegroundColor Yellow
    exit 1
}

$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
Write-Host "[ok] manifest 載入: $($manifest.bundle_name)" -ForegroundColor Green
Write-Host "    打包時間: $($manifest.built_at)"
Write-Host "    打包者:   $($manifest.built_by) @ $($manifest.built_on)"
Write-Host "    檔案數:   $($manifest.files.Count)"

# ===== 2. 驗證每個檔案 =====
$ok = 0
$failed = 0
$missing = 0
$skipped = 0

$totalFiles = $manifest.files.Count
$idx = 0

foreach ($f in $manifest.files) {
    $idx++
    $relPath = $f.path
    $fullPath = Join-Path $BundleRoot $relPath

    # Quick mode: 只查 installers/
    if ($QuickMode -and ($relPath -notlike 'installers*')) {
        $skipped++
        continue
    }

    if (-not (Test-Path $fullPath)) {
        Write-Host "[MISSING] $relPath" -ForegroundColor Red
        $missing++
        continue
    }

    # 計算 SHA256
    Write-Progress -Activity "驗證中" -Status "($idx/$totalFiles) $relPath" -PercentComplete ($idx * 100 / $totalFiles)
    $actualHash = (Get-FileHash $fullPath -Algorithm SHA256).Hash

    if ($actualHash -eq $f.sha256) {
        $ok++
    } else {
        Write-Host "[FAIL] $relPath" -ForegroundColor Red
        Write-Host "       Expected: $($f.sha256)" -ForegroundColor DarkRed
        Write-Host "       Actual:   $actualHash" -ForegroundColor DarkRed
        $failed++
    }
}
Write-Progress -Activity "驗證中" -Completed

# ===== 3. 額外檢查: 關鍵檔案是否在 =====
$criticalFiles = @(
    'deploy\offline\install_offline.ps1',
    'deploy\00_check_prereqs.ps1',
    'scripts\health_check.ps1',
    'scripts\tail_log.ps1',
    'sql\01_create_db.sql',
    'portal\requirements.txt',
    'docs\deployment_sop.md'
)

Write-Host "`n--- 關鍵檔案存在性檢查 ---" -ForegroundColor Cyan
$missingCritical = 0
foreach ($c in $criticalFiles) {
    $p = Join-Path $BundleRoot $c
    if (Test-Path $p) {
        Write-Host "[OK]  $c" -ForegroundColor Green
    } else {
        Write-Host "[!!!] $c (缺少關鍵檔)" -ForegroundColor Red
        $missingCritical++
    }
}

# ===== 4. installers 大檔特別檢查 =====
Write-Host "`n--- 重要安裝檔大小檢查 ---" -ForegroundColor Cyan

# 特別警告: SSEI downloader 不該出現在 USB
$sseiPath = Join-Path $BundleRoot 'installers\SQL2022-SSEI-Expr.exe'
if (Test-Path $sseiPath) {
    Write-Host "[警告] 偵測到 SSEI downloader (SQL2022-SSEI-Expr.exe)" -ForegroundColor Yellow
    Write-Host "       這只是下載器, 內網沒用 (它本身要連網才能跑)" -ForegroundColor Yellow
    Write-Host "       USB / bundle 應該只有 SQLEXPR_x64_ENU.exe (~250 MB 完整離線版)" -ForegroundColor Yellow
}

$expectedSizes = @{
    'installers\SQLEXPR_x64_ENU.exe'              = @{ Min = 200; Label = 'SQL Express 完整版 (必須)' }
    'installers\python-3.11.9-amd64.exe'          = @{ Min = 20;  Label = 'Python 3.11' }
    'installers\vc_redist.x64.exe'                = @{ Min = 20;  Label = 'VC++ Redistributable' }
    'installers\rewrite_amd64_en-US.msi'          = @{ Min = 5;   Label = 'URL Rewrite' }
    'installers\requestRouter_amd64.msi'          = @{ Min = 5;   Label = 'ARR' }
    'installers\nssm-2.24.zip'                    = @{ Min = 0.3; Label = 'NSSM' }
}
foreach ($file in $expectedSizes.Keys) {
    $p = Join-Path $BundleRoot $file
    $info = $expectedSizes[$file]
    if (Test-Path $p) {
        $sizeMB = (Get-Item $p).Length / 1MB
        if ($sizeMB -ge $info.Min) {
            Write-Host ("[OK]  {0,-45} {1:N1} MB" -f $info.Label, $sizeMB) -ForegroundColor Green
        } else {
            Write-Host ("[WARN] {0,-45} {1:N1} MB (預期 >{2} MB, 可能不完整)" -f $info.Label, $sizeMB, $info.Min) -ForegroundColor Yellow
        }
    } else {
        Write-Host ("[!!!] {0,-45} 缺少" -f $info.Label) -ForegroundColor Red
    }
}

# ===== 5. 統計 =====
Write-Host "`n=== 驗證結果 ===" -ForegroundColor Cyan
Write-Host "OK      : $ok"      -ForegroundColor Green
Write-Host "FAIL    : $failed"  -ForegroundColor $(if ($failed -gt 0) { 'Red' } else { 'DarkGray' })
Write-Host "MISSING : $missing" -ForegroundColor $(if ($missing -gt 0) { 'Red' } else { 'DarkGray' })
Write-Host "SKIPPED : $skipped (quick mode)" -ForegroundColor DarkGray
Write-Host ""

if ($failed -eq 0 -and $missing -eq 0 -and $missingCritical -eq 0) {
    Write-Host "✓ bundle 完整, 可以繼續跑 install_offline.ps1" -ForegroundColor Green
    exit 0
} else {
    Write-Host "✗ bundle 有問題, 不要繼續安裝" -ForegroundColor Red
    Write-Host "  可能原因:" -ForegroundColor Yellow
    Write-Host "  1. USB 拷貝時檔案被截斷"
    Write-Host "  2. zip 解壓失敗 (部分檔損毀)"
    Write-Host "  3. 防毒軟體刪除某些 exe / msi"
    Write-Host "  4. bundle 從外網打包時某些檔下載失敗"
    Write-Host ""
    Write-Host "解法: 重新打包 bundle 或重新拷貝 USB" -ForegroundColor Yellow
    exit 1
}
