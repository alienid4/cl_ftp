# extract_pyrpms_from_bundle.ps1 - 從 v2.1.0 offline bundle 挖出 Python EPEL RPMs
#
# 用途: 替代 GitHub Actions 自動打包 (那個還在 debug)
#       直接用既有的 v2.1.0 release tar.gz, 挑出 Portal 需要的 Python RPMs
#
# 用法:
#   .\extract_pyrpms_from_bundle.ps1
#
# 流程:
#   1. 從 GitHub release 下載 v2.1.0 bundle (148 MB) 到 PC
#   2. 用 tar 解壓
#   3. 挑出 python3-flask*, werkzeug*, gunicorn* 等 RPM
#   4. 重新打成小 tar (sf-epel-pyrpms.tar.gz, ~2-5 MB)
#   5. 放到 release-zip/ 給 xfer_to_sf.ps1 用

$ErrorActionPreference = "Stop"

function Step($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }
function Ok($msg)   { Write-Host "[ok] $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "[warn] $msg" -ForegroundColor Yellow }
function Fail($msg) { Write-Host "[FAIL] $msg" -ForegroundColor Red; exit 1 }

$BundleUrl = "https://github.com/alienid4/cl_ftp/releases/download/v2.1.0/sf-rhel-bundle-20260520_0930.tar.gz"
$BundleFile = "C:\Temp\sf-rhel-bundle.tar.gz"
$ExtractDir = "C:\Temp\sf-rhel-bundle-extracted"
$OutputTar  = "release-zip\sf-epel-pyrpms.tar.gz"

# Portal 需要的 Python RPM 套件名 (前綴匹配)
$NeededPrefixes = @(
    "python3-flask-",
    "python3-flask-login-",
    "python3-flask-session-",
    "python3-werkzeug-",
    "python3-gunicorn-",
    "python3-jinja2-",
    "python3-itsdangerous-",
    "python3-click-",
    "python3-markupsafe-",
    "python3-blinker-",
    "python3-ldap-",
    "python3-pyjwt-",
    "python3-pyldap-",
    "python3-pyasn1-"
)

# === Step 1: 下載 bundle ===
Step "Step 1: 下載 v2.1.0 bundle (148 MB)"

if (-not (Test-Path "C:\Temp")) {
    New-Item -ItemType Directory -Path "C:\Temp" | Out-Null
}

if (Test-Path $BundleFile) {
    $size = (Get-Item $BundleFile).Length / 1MB
    Warn "$BundleFile 已存在 ($([math]::Round($size, 1)) MB), skip 下載"
} else {
    Write-Host "[exec] curl -L -o $BundleFile $BundleUrl"
    curl.exe -L -o $BundleFile $BundleUrl
    if ($LASTEXITCODE -ne 0) {
        Fail "下載失敗"
    }
    $size = (Get-Item $BundleFile).Length / 1MB
    Ok "下載完成 ($([math]::Round($size, 1)) MB)"
}

# === Step 2: 解壓 ===
Step "Step 2: 解壓"

if (Test-Path $ExtractDir) {
    Warn "$ExtractDir 已存在, 清掉"
    Remove-Item -Recurse -Force $ExtractDir
}
New-Item -ItemType Directory -Path $ExtractDir | Out-Null

Write-Host "[exec] tar xzf $BundleFile ..."
tar -xzf $BundleFile -C $ExtractDir
if ($LASTEXITCODE -ne 0) {
    Fail "tar 解壓失敗"
}
Ok "解壓完成"

# === Step 3: 找 RPM 目錄 ===
Step "Step 3: 找 RPM 目錄"

# bundle 內可能放在 sf-rhel*-bundle/rpms/ 或 rpms/ 或 packages/
$rpmDir = Get-ChildItem -Path $ExtractDir -Recurse -Filter "*.rpm" -ErrorAction SilentlyContinue |
          Select-Object -First 1 |
          Select-Object -ExpandProperty Directory |
          Select-Object -First 1

if (-not $rpmDir) {
    Fail "在 $ExtractDir 找不到任何 .rpm 檔"
}
Ok "RPM 目錄: $rpmDir"

# === Step 4: 挑出 Python EPEL RPMs ===
Step "Step 4: 挑出 Portal 需要的 Python RPMs"

$tempPick = Join-Path $ExtractDir "picked_rpms"
New-Item -ItemType Directory -Path $tempPick -Force | Out-Null

$pickedCount = 0
$pickedFiles = @()

foreach ($prefix in $NeededPrefixes) {
    $matches = Get-ChildItem -Path $rpmDir -Filter "${prefix}*.rpm" -ErrorAction SilentlyContinue
    if ($matches) {
        foreach ($m in $matches) {
            Copy-Item $m.FullName -Destination $tempPick
            $pickedFiles += $m.Name
            $pickedCount++
        }
    } else {
        Warn "找不到 $prefix*.rpm"
    }
}

if ($pickedCount -lt 5) {
    Fail "挑到 $pickedCount 個太少, bundle 內可能不含 Python EPEL 套件"
}

Ok "挑到 $pickedCount 個 RPM:"
$pickedFiles | ForEach-Object { Write-Host "  - $_" }

# === Step 5: 寫 MANIFEST + README ===
Step "Step 5: 寫 manifest"

@"
SF Portal EPEL Python RPM bundle
================================

來源:    v2.1.0 offline bundle
挑取時間: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
RPM 數:  $pickedCount

對應 fix_portal.sh Step 1b
"@ | Set-Content -Encoding UTF8 (Join-Path $tempPick "README.txt")

# manifest
Get-ChildItem $tempPick -Filter "*.rpm" | Select-Object -ExpandProperty Name | Sort-Object |
    Set-Content -Encoding UTF8 (Join-Path $tempPick "MANIFEST.txt")

# === Step 6: 打 tar ===
Step "Step 6: 打 tar"

if (-not (Test-Path "release-zip")) {
    New-Item -ItemType Directory -Path "release-zip" | Out-Null
}

# 把 picked_rpms 目錄改名成 rpms (跟 build_epel_pyrpms.sh 一致)
$tarRpms = Join-Path $ExtractDir "rpms"
if (Test-Path $tarRpms) { Remove-Item -Recurse -Force $tarRpms }
Move-Item $tempPick $tarRpms

# 用 tar 打 (Windows 10+ 內建)
Push-Location $ExtractDir
tar -czf "C:\ClaudeHome\SFTP\$OutputTar" rpms
$tarOk = $LASTEXITCODE
Pop-Location

if ($tarOk -ne 0) {
    Fail "tar 打包失敗"
}

# sha256
$sha = (Get-FileHash $OutputTar -Algorithm SHA256).Hash.ToLower()
"$sha  $(Split-Path $OutputTar -Leaf)" | Set-Content -Encoding UTF8 "$OutputTar.sha256"

$tarSize = (Get-Item $OutputTar).Length / 1MB
Ok "Output: $OutputTar ($([math]::Round($tarSize, 2)) MB)"
Write-Host "SHA-256: $sha"

# === Step 7: 提示下一步 ===
Step "完成 - 下一步"
Write-Host ""
Write-Host "1. 推到 SF 主機:" -ForegroundColor Cyan
Write-Host "   .\xfer_to_sf.ps1 -SfHost <你的-SF-IP>" -ForegroundColor White
Write-Host ""
Write-Host "2. (可選) Commit 到 git, 讓其他人也能用:" -ForegroundColor Cyan
Write-Host "   git add $OutputTar $OutputTar.sha256" -ForegroundColor White
Write-Host "   git commit -m 'add EPEL Python RPM bundle (manual extract from v2.1.0)'" -ForegroundColor White
Write-Host "   git push" -ForegroundColor White
