# pack_local_rpms.ps1 - 把 USER 手動下載的 RPM 資料夾打成 sf-epel-pyrpms.tar.gz
#
# 對應流程:
#   1. USER 用瀏覽器點 7 個 EPEL 直連連結, 下載到一個資料夾
#   2. 跑本腳本, 自動打成 tar.gz
#   3. .\xfer_to_sf.ps1 推到 SF
#
# 用法:
#   .\pack_local_rpms.ps1 -SrcDir C:\Temp\epel-rpms

param(
    [Parameter(Mandatory=$true)]
    [string]$SrcDir,

    [string]$OutputTar = "release-zip\sf-epel-pyrpms.tar.gz"
)

$ErrorActionPreference = "Stop"

function Step($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }
function Ok($msg)   { Write-Host "[ok] $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "[warn] $msg" -ForegroundColor Yellow }
function Fail($msg) { Write-Host "[FAIL] $msg" -ForegroundColor Red; exit 1 }

# === Step 1: 驗證來源目錄 ===
Step "Step 1: 檢查 $SrcDir"

if (-not (Test-Path $SrcDir)) {
    Fail "$SrcDir 不存在"
}

$rpmFiles = Get-ChildItem -Path $SrcDir -Filter "*.rpm"
if ($rpmFiles.Count -lt 5) {
    Fail "資料夾內只有 $($rpmFiles.Count) 個 .rpm, 太少 (需要 7 個). 確認 7 個 EPEL URL 都下載完成"
}

Ok "找到 $($rpmFiles.Count) 個 RPM:"
$rpmFiles | ForEach-Object {
    $sizeMB = [math]::Round($_.Length / 1KB, 1)
    Write-Host ("  - {0} ({1} KB)" -f $_.Name, $sizeMB)
}

# 必要套件清單 (前綴)
$RequiredPrefixes = @(
    "python3-flask-",
    "python3-werkzeug-",
    "python3-gunicorn-",
    "python3-itsdangerous-",
    "python3-click-",
    "python3-blinker-",
    "python3-ldap3-"
)

$missing = @()
foreach ($prefix in $RequiredPrefixes) {
    # 必須以 prefix 起頭, 後面緊接數字版本 (避免 python3-click-default-group 也算進來)
    $match = $rpmFiles | Where-Object { $_.Name -match "^$([regex]::Escape($prefix))\d" }
    if (-not $match) {
        $missing += $prefix
    }
}

if ($missing.Count -gt 0) {
    Warn "缺少必要套件:"
    $missing | ForEach-Object { Write-Host "  - $_*.rpm" }
    Write-Host ""
    Write-Host "從這裡點連結補抓:" -ForegroundColor Cyan
    Write-Host "  https://dl.fedoraproject.org/pub/epel/9/Everything/x86_64/Packages/p/" -ForegroundColor White
    Fail "缺套件, 不繼續打包"
}

Ok "必要套件齊全"

# === Step 2: 準備暫存目錄 ===
Step "Step 2: 準備打包"

$workDir = Join-Path ([System.IO.Path]::GetTempPath()) "sf-epel-pack-$(Get-Random)"
$rpmsDir = Join-Path $workDir "rpms"
New-Item -ItemType Directory -Path $rpmsDir -Force | Out-Null

# 拷 RPM
$rpmFiles | ForEach-Object {
    Copy-Item $_.FullName -Destination $rpmsDir
}

# 寫 README 與 MANIFEST (跟 build_epel_pyrpms.sh 一致)
@"
SF Portal EPEL Python RPM bundle (manual)
=========================================

來源:    USER 手動從 dl.fedoraproject.org 下載
打包時間: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
RPM 數:  $($rpmFiles.Count)

對應 fix_portal.sh Step 1b 自動讀取.

安裝 (在 SF 主機, 完全離線):
  cd /tmp/sf-epel-pyrpms/rpms
  sudo dnf install -y --disablerepo='*' --nogpgcheck ./*.rpm
"@ | Set-Content -Encoding UTF8 (Join-Path $rpmsDir "README.txt")

Get-ChildItem $rpmsDir -Filter "*.rpm" | Select-Object -ExpandProperty Name | Sort-Object |
    Set-Content -Encoding UTF8 (Join-Path $rpmsDir "MANIFEST.txt")

Ok "暫存目錄: $workDir"

# === Step 3: 打 tar ===
Step "Step 3: 打 tar"

if (-not (Test-Path "release-zip")) {
    New-Item -ItemType Directory -Path "release-zip" | Out-Null
}

Push-Location $workDir
tar -czf "C:\ClaudeHome\SFTP\$OutputTar" rpms
$tarOk = $LASTEXITCODE
Pop-Location

if ($tarOk -ne 0) {
    Fail "tar 失敗"
}

# sha256
$sha = (Get-FileHash $OutputTar -Algorithm SHA256).Hash.ToLower()
"$sha  $(Split-Path $OutputTar -Leaf)" | Set-Content -Encoding UTF8 "$OutputTar.sha256"

$tarSize = (Get-Item $OutputTar).Length / 1MB
Ok "Output: $OutputTar ($([math]::Round($tarSize, 2)) MB)"
Write-Host "SHA-256: $sha"

# 清暫存
Remove-Item -Recurse -Force $workDir -ErrorAction SilentlyContinue

# === Step 4: 提示下一步 ===
Step "完成"

Write-Host ""
Write-Host "下一步 - 推到 SF:" -ForegroundColor Cyan
Write-Host "  .\xfer_to_sf.ps1 -SfHost <SF-IP>" -ForegroundColor White
Write-Host ""
Write-Host "之後 SF 跑:" -ForegroundColor Cyan
Write-Host "  ssh root@<SF-IP> 'sudo bash /opt/sf/release-zip/latest-fix-portal.sh'" -ForegroundColor White
