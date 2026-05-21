# xfer_to_sf.ps1 - 把 release-zip/ 從 PC 推到 SF 主機 /opt/sf/release-zip/
#
# 用法 (在 C:\ClaudeHome\SFTP\ 跑):
#   .\xfer_to_sf.ps1 -SfHost <SF-IP-or-hostname>
#
# 例:
#   .\xfer_to_sf.ps1 -SfHost 10.92.198.16
#   .\xfer_to_sf.ps1 -SfHost 10.92.198.16 -SfUser admin
#
# 流程:
#   1. git pull (確保最新)
#   2. 確認 release-zip/sf-epel-pyrpms.tar.gz 存在 (要 GitHub Actions 跑完才會有)
#   3. scp release-zip/ -> sf:/opt/sf/release-zip/
#   4. 印下一步指令 (要在 SF 跑的)

param(
    [Parameter(Mandatory=$true)]
    [string]$SfHost,

    [string]$SfUser = "root",

    [string]$SfPath = "/opt/sf",

    [switch]$SkipGitPull
)

$ErrorActionPreference = "Stop"

function Write-Step($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "[ok] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "[warn] $msg" -ForegroundColor Yellow }
function Write-Fail($msg) { Write-Host "[FAIL] $msg" -ForegroundColor Red; exit 1 }

# === Step 1: git pull ===
if (-not $SkipGitPull) {
    Write-Step "Step 1: git pull (確保拿到最新 EPEL tar)"
    git pull
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "git pull 失敗"
    }
    Write-Ok "git pull 完成"
}

# === Step 2: 確認 EPEL tar 存在 ===
Write-Step "Step 2: 確認 release-zip/ 有 EPEL tar"

$tarPath = "release-zip\sf-epel-pyrpms.tar.gz"
if (-not (Test-Path $tarPath)) {
    Write-Warn "找不到 $tarPath"
    Write-Host ""
    Write-Host "GitHub Actions 可能還沒跑完, 確認:" -ForegroundColor Yellow
    Write-Host "  https://github.com/alienid4/cl_ftp/actions" -ForegroundColor White
    Write-Host ""
    Write-Host "等綠勾後 git pull 一次再跑本腳本" -ForegroundColor Yellow
    exit 1
}

$tarSize = (Get-Item $tarPath).Length / 1MB
Write-Ok "找到 $tarPath ($([math]::Round($tarSize, 2)) MB)"

# 列要傳的檔
$filesToSend = @(
    "release-zip\sf-epel-pyrpms.tar.gz",
    "release-zip\sf-epel-pyrpms.tar.gz.sha256",
    "release-zip\latest-fix-portal.sh",
    "release-zip\latest-diagnose.sh",
    "release-zip\latest-net-check.sh"
)

Write-Host ""
Write-Host "要傳的檔:"
$filesToSend | ForEach-Object {
    if (Test-Path $_) {
        $size = (Get-Item $_).Length
        Write-Host ("  {0} ({1} bytes)" -f $_, $size)
    } else {
        Write-Warn "  $_ 不存在, skip"
    }
}

# === Step 3: scp ===
Write-Step "Step 3: scp 到 $SfUser@$SfHost`:$SfPath/release-zip/"

# 確認 SF 有目錄
Write-Host "[exec] ssh 建目錄..."
ssh "$SfUser@$SfHost" "mkdir -p $SfPath/release-zip"
if ($LASTEXITCODE -ne 0) {
    Write-Fail "ssh 失敗, 確認 IP / 帳號 / SSH key"
}

# scp 全部
Write-Host "[exec] scp release-zip/* ..."
$existingFiles = $filesToSend | Where-Object { Test-Path $_ }
$scpArgs = $existingFiles + @("$SfUser@$SfHost`:$SfPath/release-zip/")
scp @scpArgs
if ($LASTEXITCODE -ne 0) {
    Write-Fail "scp 失敗"
}
Write-Ok "scp 完成"

# 驗 SHA-256
Write-Host ""
Write-Host "[exec] SF 端驗 SHA-256..."
ssh "$SfUser@$SfHost" "cd $SfPath/release-zip && sha256sum -c sf-epel-pyrpms.tar.gz.sha256"
if ($LASTEXITCODE -eq 0) {
    Write-Ok "SHA-256 驗證 OK"
} else {
    Write-Warn "SHA-256 驗證失敗 (傳輸可能損壞)"
}

# === Step 4: 印下一步 ===
Write-Step "完成 - SF 端跑這一行 (不需要網路)"
Write-Host ""
Write-Host "  ssh $SfUser@$SfHost" -ForegroundColor Yellow
Write-Host "  sudo bash $SfPath/release-zip/latest-fix-portal.sh" -ForegroundColor Yellow
Write-Host ""
Write-Host "或直接從你 PC 一行跑:" -ForegroundColor Cyan
Write-Host "  ssh $SfUser@$SfHost 'sudo bash $SfPath/release-zip/latest-fix-portal.sh'" -ForegroundColor White
Write-Host ""
