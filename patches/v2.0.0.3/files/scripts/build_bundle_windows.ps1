<#
.SYNOPSIS
    [Windows PC] 用 Docker + Rocky Linux 9 打包 SF 離線安裝包

.DESCRIPTION
    給「只有 Windows PC 沒 RHEL 機器」的使用者用。
    在 Windows PowerShell 跑這支, 自動:
    1. 確認 Docker Desktop 跑著
    2. Pull Rocky Linux 9 image (一次性, ~70 MB)
    3. 在 container 內跑 build_offline_bundle.sh
    4. 把 tar.gz 輸出到當前目錄

    輸出檔 (約 225 MB) 拷到 USB, 帶到 SF 主機 (內網) 解壓 + 跑 install_offline.sh。

.PARAMETER OutputDir
    輸出目錄, 預設當前目錄

.EXAMPLE
    .\build_bundle_windows.ps1

.EXAMPLE
    # 輸出到 D:\sf_install\
    .\build_bundle_windows.ps1 -OutputDir D:\sf_install

.NOTES
    Patch: v2.0.0.3
    需要 Windows PC 有 Docker Desktop (一次性安裝)
    https://www.docker.com/products/docker-desktop/
#>
[CmdletBinding()]
param(
    [string]$OutputDir = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  SF 離線安裝包 — Windows PC 打包工具 (用 Docker)" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

# === 0. 檢查 Docker ===
Write-Host "[1/4] 檢查 Docker..." -ForegroundColor Yellow

$dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
if (-not $dockerCmd) {
    Write-Host "[FAIL] 沒安裝 Docker Desktop" -ForegroundColor Red
    Write-Host ""
    Write-Host "請先裝 Docker Desktop for Windows:" -ForegroundColor Yellow
    Write-Host "  https://www.docker.com/products/docker-desktop/"
    Write-Host ""
    Write-Host "裝完啟動 Docker Desktop, 再重跑這支腳本"
    Write-Host ""
    Write-Host "或者改用 WSL2 (Windows 內建, 免裝 Docker):"
    Write-Host "  詳見 docs/runbook/v2.0.0.3_20260520_1500_windows_pc_build.md"
    exit 1
}

# 確認 Docker daemon 在跑
try {
    $null = docker version 2>&1
    Write-Host "[ok] Docker 已安裝且 daemon 跑著" -ForegroundColor Green
} catch {
    Write-Host "[FAIL] Docker daemon 沒跑, 請打開 Docker Desktop" -ForegroundColor Red
    exit 1
}

# === 1. 準備輸出目錄 ===
Write-Host ""
Write-Host "[2/4] 準備輸出目錄..." -ForegroundColor Yellow

if (-not (Test-Path $OutputDir)) {
    New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null
}
$OutputDir = (Resolve-Path $OutputDir).Path
Write-Host "[ok] 輸出目錄: $OutputDir" -ForegroundColor Green

# === 2. Pull Rocky Linux 9 image ===
Write-Host ""
Write-Host "[3/4] Pull Rocky Linux 9 image (第一次 ~70 MB, 之後 cache)..." -ForegroundColor Yellow

docker pull rockylinux:9 2>&1 | Select-String -Pattern '(Pulling|Downloaded|Status|Image is up to date)'

# === 3. 跑 container 打包 ===
Write-Host ""
Write-Host "[4/4] 在 Rocky 9 container 內打包..." -ForegroundColor Yellow
Write-Host "      (這步約 5-10 分鐘, 抓 200+ MB RPM + Python wheels)"
Write-Host ""

# Windows path → Docker path 轉換
$dockerMount = $OutputDir -replace '\\', '/' -replace '^([A-Za-z]):', '/$1' | ForEach-Object { $_.ToLower() }

# 跑 container, 內部:
# 1. dnf install git python3-pip
# 2. clone repo
# 3. 跑 build_offline_bundle.sh, 輸出到 /output
$containerScript = @'
set -e
echo "=== Container 環境 ==="
cat /etc/redhat-release
echo ""

# 1. 裝基礎工具
dnf install -y --quiet git python3 python3-pip openssl tar bzip2 2>&1 | tail -5

# 2. clone repo
echo "Cloning repo..."
git clone --depth=1 https://github.com/alienid4/cl_ftp /tmp/sf 2>&1 | tail -3

# 3. 跑打包 (輸出到 /output, 對映 Windows PC 的 OutputDir)
cd /tmp/sf
bash ./deploy-rhel/build_offline_bundle.sh /output/sf-rhel-bundle

# 4. 顯示結果
echo ""
echo "=== 完成 ==="
ls -lah /output/*.tar.gz /output/*.sha256 2>/dev/null
'@

# 用 docker run 跑 (Windows path 用 mount)
$dockerArgs = @(
    'run', '--rm',
    '-v', "${OutputDir}:/output",
    'rockylinux:9',
    'bash', '-c', $containerScript
)

& docker @dockerArgs

# === 4. 驗證輸出 ===
Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  完成" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

$tarballs = Get-ChildItem -Path $OutputDir -Filter 'sf-rhel-bundle-*.tar.gz' -ErrorAction SilentlyContinue
if ($tarballs) {
    foreach ($tb in $tarballs) {
        $sizeMB = '{0:N1}' -f ($tb.Length / 1MB)
        Write-Host ""
        Write-Host "輸出檔:" -ForegroundColor Green
        Write-Host "  $($tb.FullName) ($sizeMB MB)" -ForegroundColor Green
    }

    $hashes = Get-ChildItem -Path $OutputDir -Filter 'sf-rhel-bundle-*.sha256' -ErrorAction SilentlyContinue
    foreach ($h in $hashes) {
        Write-Host "  $($h.FullName)" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "下一步:" -ForegroundColor Cyan
    Write-Host "  1. 拷 .tar.gz 跟 .sha256 到 USB"
    Write-Host "  2. USB 接 SF 主機, mount"
    Write-Host "  3. SF 主機:"
    Write-Host "       sha256sum -c sf-rhel-bundle-*.sha256    # 驗 hash"
    Write-Host "       tar xzf sf-rhel-bundle-*.tar.gz          # 解壓"
    Write-Host "       cd sf-rhel-bundle/"
    Write-Host "       sudo SF_ACCOUNTS=u01t SF_PASSWORD='1qaz@WSX' ./install_offline.sh"
    Write-Host ""
} else {
    Write-Host "[FAIL] 沒找到輸出檔, 看上面 docker output 找錯" -ForegroundColor Red
    exit 1
}
