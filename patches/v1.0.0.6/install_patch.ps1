<#
.SYNOPSIS
    [Patch v1.0.0.6] 通用 patch 安裝器 — 任意目錄都能跑。
.DESCRIPTION
    取代舊版 apply.ps1 (只能在 SF-PROJECT-ROOT 結構下跑)。
    支援三種模式:
      1. 預設 (auto): 偵測 SF-PROJECT-ROOT, 拷到原專案結構
      2. -Here:      拷到當前目錄 (好處: 下載單個 patch zip, 解壓後在那目錄跑就好)
      3. -Target <path>: 拷到指定目錄

    本 patch 包含:
      - scripts/install_openssh_portable.ps1 (改進: auto-find OpenSSH-Win64.zip)
      - scripts/fetch_openssh_portable.ps1 (新增: 外網 PC 抓 zip + SHA256)
.PARAMETER Here
    拷到當前目錄 (Get-Location), 不偵測 SF root。
.PARAMETER Target
    拷到指定目錄 (絕對或相對路徑)。
.PARAMETER ProjectRoot
    指定 SF-PROJECT-ROOT (預設自動偵測為腳本上兩層)。
.PARAMETER DryRun
    只列出將執行的動作, 不實際做事。
.EXAMPLE
    # 在 SF-PROJECT-ROOT/patches/v1.0.0.6/ 下跑 (自動偵測)
    .\install_patch.ps1
.EXAMPLE
    # 任意目錄下載解壓後跑, 拷到當前目錄
    .\install_patch.ps1 -Here
.EXAMPLE
    # 指定 SF 主機部署位置
    .\install_patch.ps1 -Target 'C:\Users\me\Desktop\sf_bundle\'
.EXAMPLE
    # 預演
    .\install_patch.ps1 -Target 'C:\Temp\' -DryRun
.NOTES
    Patch: v1.0.0.6
#>
[CmdletBinding(DefaultParameterSetName='Auto')]
param(
    [Parameter(ParameterSetName='Here')]
    [switch]$Here,

    [Parameter(ParameterSetName='Target')]
    [string]$Target,

    [Parameter(ParameterSetName='Auto')]
    [string]$ProjectRoot,

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

Write-Host "`n=== Install Patch v1.0.0.6 ===" -ForegroundColor Cyan
Write-Host "通用 patch 安裝器 (任意目錄可跑)" -ForegroundColor DarkCyan

# 決定 destination root
$destRoot = $null
switch ($PSCmdlet.ParameterSetName) {
    'Here' {
        $destRoot = (Get-Location).Path
        Write-Host "[mode] -Here: 拷到當前目錄"
    }
    'Target' {
        if (-not (Test-Path $Target)) {
            if (-not $DryRun) {
                New-Item -Path $Target -ItemType Directory -Force | Out-Null
                Write-Host "[create] $Target"
            }
        }
        $destRoot = (Resolve-Path $Target).Path
        Write-Host "[mode] -Target: $destRoot"
    }
    default {
        # Auto mode: 偵測 SF root
        if (-not $ProjectRoot) {
            # 預期結構: <root>/patches/v1.0.0.6/install_patch.ps1
            $candidate = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
            $hasScripts = Test-Path (Join-Path $candidate 'scripts')
            $hasDeploy = Test-Path (Join-Path $candidate 'deploy')
            if ($hasScripts -or $hasDeploy) {
                $ProjectRoot = $candidate
                Write-Host "[auto] 偵測到 SF-PROJECT-ROOT: $ProjectRoot"
            } else {
                Write-Host "[FAIL] 自動偵測失敗 — 不在 SF-PROJECT-ROOT 結構下" -ForegroundColor Red
                Write-Host ""
                Write-Host "請改用以下方式之一:" -ForegroundColor Yellow
                Write-Host "  1. -Here (拷到當前目錄):"
                Write-Host "     .\install_patch.ps1 -Here"
                Write-Host ""
                Write-Host "  2. -Target <path> (指定目錄):"
                Write-Host "     .\install_patch.ps1 -Target 'C:\Users\me\Desktop\sf_bundle\'"
                Write-Host ""
                Write-Host "  3. -ProjectRoot <path> (手動指定 SF root):"
                Write-Host "     .\install_patch.ps1 -ProjectRoot 'C:\Users\me\Desktop\sf_bundle\'"
                exit 1
            }
        }
        $destRoot = (Resolve-Path $ProjectRoot).Path
    }
}

Write-Host ""
Write-Host "[dest] $destRoot"

# 找 files/ 目錄
$filesDir = Join-Path $PSScriptRoot 'files'
if (-not (Test-Path $filesDir)) {
    Write-Host "[FAIL] 找不到 files/ 目錄: $filesDir" -ForegroundColor Red
    Write-Host "       此 patch 結構壞了, 請重新下載"
    exit 1
}

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$copied = 0; $skipped = 0; $backedUp = 0

Get-ChildItem $filesDir -Recurse -File | ForEach-Object {
    $relPath = $_.FullName.Substring($filesDir.Length + 1)
    $srcFile = $_.FullName
    $dstFile = Join-Path $destRoot $relPath
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
        Write-Host "  [dry] $srcFile -> $dstFile"
    } else {
        Copy-Item $srcFile $dstFile -Force
        Write-Host "  [ok] $dstFile" -ForegroundColor Green
        $copied++
    }
}

Write-Host ""
Write-Host "===== 套用結果 =====" -ForegroundColor Cyan
Write-Host "  覆蓋: $copied / Skip: $skipped / 備份: $backedUp"
Write-Host ""

if (-not $DryRun) {
    Write-Host "✓ Patch v1.0.0.6 套用完成" -ForegroundColor Green
    Write-Host ""
    Write-Host "下一步:" -ForegroundColor Cyan

    if ($PSCmdlet.ParameterSetName -eq 'Here') {
        Write-Host "  在當前目錄找到拷過來的 scripts/install_openssh_portable.ps1"
        Write-Host "  把 OpenSSH-Win64.zip 也放當前目錄, 跑:"
        Write-Host "    .\scripts\install_openssh_portable.ps1"
    } else {
        Write-Host "  1. 外網 PC 跑 scripts\fetch_openssh_portable.ps1 抓 OpenSSH-Win64.zip"
        Write-Host "  2. USB 拷到 SF 主機, 放 D:\install\ 或當前目錄"
        Write-Host "  3. cd '$destRoot'"
        Write-Host "  4. .\scripts\install_openssh_portable.ps1"
        Write-Host "     (auto-find 會自動找到 zip)"
    }
}
