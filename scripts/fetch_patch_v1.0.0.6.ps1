<#
.SYNOPSIS
    [一鍵抓] sf-patch v1.0.0.6 全部檔到當前目錄, 不需要 release / zip。
.DESCRIPTION
    直接從 GitHub main branch 抓 patches/v1.0.0.6/ 下所有檔。
    需要外網。SF 主機沒外網時, 在有外網的 PC 跑這支, 整個目錄拷進 SF 主機。

    抓完目錄結構:
      .\install_patch.ps1
      .\run_patch.cmd
      .\PATCH_NOTE.md
      .\README.md
      .\files\scripts\install_openssh_portable.ps1
      .\files\scripts\fetch_openssh_portable.ps1
.EXAMPLE
    .\fetch_patch_v1.0.0.6.ps1
#>
[CmdletBinding()]
param(
    [string]$OutDir = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'
Write-Host "`n=== Fetch SF Patch v1.0.0.6 ===" -ForegroundColor Cyan

$base = 'https://raw.githubusercontent.com/alienid4/cl_ftp/main/patches/v1.0.0.6'
$files = @(
    'install_patch.ps1',
    'run_patch.cmd',
    'PATCH_NOTE.md',
    'README.md',
    'files/scripts/install_openssh_portable.ps1',
    'files/scripts/fetch_openssh_portable.ps1'
)

if (-not (Test-Path $OutDir)) { New-Item $OutDir -ItemType Directory -Force | Out-Null }
$OutDir = (Resolve-Path $OutDir).Path

$ok = 0; $fail = 0
foreach ($f in $files) {
    $url = "$base/$f"
    $dst = Join-Path $OutDir ($f -replace '/', '\')
    $dstDir = Split-Path $dst -Parent
    if (-not (Test-Path $dstDir)) { New-Item $dstDir -ItemType Directory -Force | Out-Null }

    Write-Host "  $f ... " -NoNewline
    try {
        Invoke-WebRequest -Uri $url -OutFile $dst -UseBasicParsing
        Write-Host "[ok] $('{0:N1}' -f ((Get-Item $dst).Length / 1KB)) KB" -ForegroundColor Green
        $ok++
    } catch {
        Write-Host "[FAIL] $($_.Exception.Message)" -ForegroundColor Red
        $fail++
    }
}

Write-Host ""
Write-Host "===== 結果: $ok ok / $fail fail =====" -ForegroundColor Cyan
Write-Host ""
Write-Host "全部檔在: $OutDir"
Write-Host ""
Write-Host "下一步:"
Write-Host "  1. 整個目錄拷到 USB"
Write-Host "  2. 帶到 SF 主機"
Write-Host "  3. 雙擊 run_patch.cmd (或 PowerShell 跑 .\install_patch.ps1)"
Write-Host "  4. 自動偵測 sf_offline_bundle_* 並套用"
