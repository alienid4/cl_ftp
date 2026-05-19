#requires -Version 5.1
<#
.SYNOPSIS
    [Win11 外網用] 抓 SF 主機需要的所有 binary 套件, 不打包, 不依賴專案目錄。
.DESCRIPTION
    這支是「**獨立的下載器**」, 在能上 Internet 的 Win11 工作站跑即可。
    完全 self-contained, 不需要 git clone 整個 SFTP 專案。

    下載完成後, 您可以:
    1. 直接把 .\sf_binaries\ 整個資料夾拷到 USB
    2. 或回到 SFTP 專案跑 build_offline_bundle.ps1 包成 zip
.PARAMETER Output
    輸出目錄, 預設當前目錄下的 sf_binaries\
.PARAMETER SkipPython
    跳過 Python wheels 下載 (沒裝 Python 時用, 但建議裝)
.PARAMETER Force
    強制重抓 (預設已存在會 skip)
.PARAMETER PythonVersion
    Python 版本, 預設 3.11.9
.EXAMPLE
    # 最簡單 — 直接跑
    .\fetch_binaries_win11.ps1
.EXAMPLE
    # 指定輸出位置
    .\fetch_binaries_win11.ps1 -Output D:\sf_binaries
.EXAMPLE
    # 跳過 Python wheels (沒裝 Python 時)
    .\fetch_binaries_win11.ps1 -SkipPython
#>
[CmdletBinding()]
param(
    [string]$Output = (Join-Path $PWD 'sf_binaries'),
    [switch]$SkipPython,
    [switch]$Force,
    [string]$PythonVersion = '3.11.9'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'Continue'  # 顯示 Invoke-WebRequest 進度

# ===== 顏色函式 =====
function Section($txt) {
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host " $txt" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Cyan
}

# ===== 目錄結構 =====
$installersDir = Join-Path $Output 'installers'
$wheelsDir = Join-Path $Output 'python_wheels'

foreach ($d in @($Output, $installersDir, $wheelsDir)) {
    if (-not (Test-Path $d)) { New-Item -Path $d -ItemType Directory -Force | Out-Null }
}

# ===== Banner =====
Section "SF Binary Downloader (Win11 外網用)"
Write-Host "輸出目錄  : $Output"
Write-Host "Python    : $(if ($SkipPython) { 'SKIP' } else { 'Include (要本機有 Python 3.11+)' })"
Write-Host "Force 重抓: $Force"
Write-Host ""
Write-Host "預估下載量: ~600 MB"
Write-Host "預估時間  : 5-30 分鐘 (依網速)"

# ===== 下載清單 =====
$downloads = @(
    [pscustomobject]@{
        Name = 'Visual C++ Redistributable x64'
        Url  = 'https://aka.ms/vs/17/release/vc_redist.x64.exe'
        File = 'vc_redist.x64.exe'
        Size = 25
        After = $null
    },
    [pscustomobject]@{
        Name = 'SQL Server 2022 Express SSEI downloader'
        Url  = 'https://download.microsoft.com/download/5/1/4/5145fe04-4d30-4b85-b0d1-39533663a2f1/SQL2022-SSEI-Expr.exe'
        File = 'SQL2022-SSEI-Expr.exe'
        Size = 5
        After = 'sql_full_download'  # 抓完跑 SSEI 抓完整版
    },
    [pscustomobject]@{
        Name = 'SQL Server Command Line Utilities (sqlcmd)'
        Url  = 'https://go.microsoft.com/fwlink/?linkid=2240795'
        File = 'MsSqlCmdLnUtils.msi'
        Size = 6
        After = $null
    },
    [pscustomobject]@{
        Name = 'URL Rewrite Module 2.1'
        Url  = 'https://download.microsoft.com/download/1/2/8/128E2E22-C1B9-44A4-BE2A-5859ED1D4592/rewrite_amd64_en-US.msi'
        File = 'rewrite_amd64_en-US.msi'
        Size = 7
        After = $null
    },
    [pscustomobject]@{
        Name = 'Application Request Routing 3.0'
        Url  = 'https://download.microsoft.com/download/E/9/8/E9849D6A-020E-47E4-9FD0-A023E99B54EB/requestRouter_amd64.msi'
        File = 'requestRouter_amd64.msi'
        Size = 7
        After = $null
    },
    [pscustomobject]@{
        Name = "Python $PythonVersion"
        Url  = "https://www.python.org/ftp/python/$PythonVersion/python-$PythonVersion-amd64.exe"
        File = "python-$PythonVersion-amd64.exe"
        Size = 25
        After = $null
    },
    [pscustomobject]@{
        Name = 'NSSM 2.24 (zip)'
        Url  = 'https://nssm.cc/release/nssm-2.24.zip'
        File = 'nssm-2.24.zip'
        Size = 0.4
        After = $null
    }
)

# ===== Step 1: 下載 =====
Section "Step 1 / 3: 下載 Microsoft + 開源套件"

foreach ($item in $downloads) {
    $dest = Join-Path $installersDir $item.File

    Write-Host ""
    Write-Host "[$($item.Name)]" -ForegroundColor Cyan
    Write-Host "  URL : $($item.Url)"
    Write-Host "  Dest: $dest"
    Write-Host "  預期: ~$($item.Size) MB"

    if ((Test-Path $dest) -and (-not $Force)) {
        $existSize = (Get-Item $dest).Length / 1MB
        if ($existSize -gt 0.1) {
            Write-Host "  [skip] 已存在 $([math]::Round($existSize, 1)) MB (用 -Force 強制重抓)" -ForegroundColor DarkGray
            continue
        }
    }

    try {
        # 用 .NET WebClient 比 Invoke-WebRequest 在大檔下載快 5-10 倍
        Add-Type -AssemblyName System.Net.Http
        $client = New-Object System.Net.WebClient
        $client.Headers.Add('User-Agent', 'Mozilla/5.0 (SF-Bundle-Fetcher)')
        $startTime = Get-Date
        $client.DownloadFile($item.Url, $dest)
        $elapsed = ((Get-Date) - $startTime).TotalSeconds
        $sizeMB = (Get-Item $dest).Length / 1MB
        $speed = if ($elapsed -gt 0) { $sizeMB / $elapsed } else { 0 }
        Write-Host ("  [ok  ] {0:N1} MB in {1:N1}s ({2:N1} MB/s)" -f $sizeMB, $elapsed, $speed) -ForegroundColor Green
    } catch {
        Write-Host "  [FAIL] $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  → 請手動下載: $($item.Url)" -ForegroundColor Yellow
        Write-Host "    存到: $dest" -ForegroundColor Yellow
    }

    # 後續動作: SSEI 抓 SQL Express 完整版
    if ($item.After -eq 'sql_full_download') {
        $fullExpr = Join-Path $installersDir 'SQLEXPR_x64_ENU.exe'
        if ((Test-Path $fullExpr) -and (-not $Force)) {
            $sizeMB = (Get-Item $fullExpr).Length / 1MB
            Write-Host "  [skip] SQL Express 完整版已存在 $([math]::Round($sizeMB, 1)) MB" -ForegroundColor DarkGray
        } else {
            Write-Host ""
            Write-Host "  → 跑 SSEI 抓 SQL Express 完整離線版 (~250 MB), 約 1-3 分鐘..." -ForegroundColor Cyan
            try {
                $proc = Start-Process -FilePath $dest -ArgumentList @(
                    '/ACTION=Download',
                    '/MEDIATYPE=Core',
                    "/MEDIAPATH=$installersDir",
                    '/QUIET'
                ) -Wait -PassThru -NoNewWindow

                if (Test-Path $fullExpr) {
                    $sizeMB = (Get-Item $fullExpr).Length / 1MB
                    Write-Host ("  [ok  ] SQL Express 完整版 {0:N0} MB" -f $sizeMB) -ForegroundColor Green

                    # 刪除 SSEI downloader — 內網用不到
                    Remove-Item $dest -Force
                    Write-Host "  [clean] 已移除 SSEI downloader (USB 不需要)" -ForegroundColor Yellow
                } else {
                    Write-Host "  [FAIL] SSEI 完整版下載失敗 (exit=$($proc.ExitCode))" -ForegroundColor Red
                    Write-Host "         請手動下載完整版, 或用 GUI 跑 SQL2022-SSEI-Expr.exe 選 Download" -ForegroundColor Yellow
                }
            } catch {
                Write-Host "  [FAIL] SSEI 執行失敗: $_" -ForegroundColor Red
            }
        }
    }
}

# ===== Step 2: Python wheels =====
if (-not $SkipPython) {
    Section "Step 2 / 3: 下載 Python 套件 wheels"

    $python = Get-Command python -ErrorAction SilentlyContinue
    if (-not $python) {
        Write-Host "[FAIL] 本機沒有 Python, 跳過 wheels 下載" -ForegroundColor Red
        Write-Host "  解法 (擇一):" -ForegroundColor Yellow
        Write-Host "  1. 先裝本機 Python: winget install Python.Python.3.11"
        Write-Host "  2. 或加 -SkipPython 參數 (但 SF 主機要另想辦法裝 Python 套件)"
    } else {
        $pyVer = & python --version 2>&1
        Write-Host "[info] 本機 Python: $pyVer"

        # 寫 requirements.txt
        $reqContent = @"
flask>=3.0
waitress>=3.0
pyodbc>=5.0
ldap3>=2.9
flask-login>=0.6
flask-session>=0.5
jinja2>=3.1
flask-wtf>=1.2
python-dotenv>=1.0
pyyaml>=6.0
apscheduler>=3.10
flask-mail>=0.10
pywin32>=306
psutil>=5.9
requests>=2.31
openpyxl>=3.1
cryptography>=42
"@
        $reqPath = Join-Path $Output 'requirements.txt'
        Set-Content -Path $reqPath -Value $reqContent -Encoding UTF8
        Write-Host "[info] 已寫 requirements.txt"

        Write-Host ""
        Write-Host "下載 wheels (Windows x64, Python 3.11)..." -ForegroundColor Cyan
        try {
            & python -m pip download `
                -r $reqPath `
                -d $wheelsDir `
                --platform win_amd64 `
                --python-version 311 `
                --only-binary=:all: `
                --no-cache-dir 2>&1 | ForEach-Object {
                if ($_ -match '^Saved ') { Write-Host "  $_" -ForegroundColor Green }
                elseif ($_ -match '^Collecting ') { Write-Host "  $_" -ForegroundColor Cyan }
                elseif ($_ -match 'ERROR|error') { Write-Host "  $_" -ForegroundColor Red }
            }
            $count = (Get-ChildItem $wheelsDir -Filter '*.whl').Count
            $totalMB = ((Get-ChildItem $wheelsDir -Filter '*.whl' | Measure-Object Length -Sum).Sum / 1MB)
            Write-Host ("[ok] 下載 {0} 個 wheel, 共 {1:N1} MB" -f $count, $totalMB) -ForegroundColor Green
        } catch {
            Write-Host "[FAIL] pip download 失敗: $_" -ForegroundColor Red
        }
    }
}

# ===== Step 3: 產生 SHA256 + 報告 =====
Section "Step 3 / 3: 產生 SHA256 + 大小報告"

$allFiles = Get-ChildItem $Output -File -Recurse
$totalBytes = ($allFiles | Measure-Object Length -Sum).Sum
$totalMB = $totalBytes / 1MB

$report = @{
    fetched_at = (Get-Date).ToString('o')
    fetched_by = "$env:USERDOMAIN\$env:USERNAME"
    fetched_on = $env:COMPUTERNAME
    total_files = $allFiles.Count
    total_bytes = $totalBytes
    total_mb = [math]::Round($totalMB, 2)
    files = @()
}

Write-Host "計算 SHA256..."
foreach ($f in $allFiles) {
    $hash = (Get-FileHash $f.FullName -Algorithm SHA256).Hash
    $rel = $f.FullName.Substring($Output.Length + 1)
    $report.files += @{
        path = $rel
        size = $f.Length
        size_mb = [math]::Round($f.Length / 1MB, 2)
        sha256 = $hash
    }
}

$report | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $Output 'fetch_manifest.json') -Encoding UTF8

# ===== 顯示報告 =====
Section "下載完成"

Write-Host "輸出位置: $Output"
Write-Host ("總大小  : {0:N1} MB ({1} 個檔)" -f $totalMB, $allFiles.Count) -ForegroundColor Green
Write-Host ""

Write-Host "--- installers/ ---" -ForegroundColor Cyan
Get-ChildItem $installersDir -File | Sort-Object Length -Descending | ForEach-Object {
    $mb = [math]::Round($_.Length / 1MB, 1)
    Write-Host ("  {0,-45} {1,8} MB" -f $_.Name, $mb)
}

if (Test-Path $wheelsDir) {
    $wheelCount = (Get-ChildItem $wheelsDir -Filter '*.whl').Count
    $wheelMB = [math]::Round((Get-ChildItem $wheelsDir -Filter '*.whl' | Measure-Object Length -Sum).Sum / 1MB, 1)
    Write-Host ""
    Write-Host "--- python_wheels/ ---" -ForegroundColor Cyan
    Write-Host ("  $wheelCount 個 wheel 檔, 共 $wheelMB MB")
}

Write-Host ""
Write-Host "--- 下一步 ---" -ForegroundColor Yellow
Write-Host "1. 確認 SF 專案碼也在外網工作站 (從 git 或 share 取)"
Write-Host "2. 把 $Output 整個拷到 SF 專案的 deploy\offline\ 下:"
Write-Host "     Copy-Item '$Output\*' '<SFTP_PROJECT>\deploy\offline\' -Recurse"
Write-Host "3. 跑打包成 zip (產生 USB 用的單一檔):"
Write-Host "     cd <SFTP_PROJECT>\deploy\offline"
Write-Host "     .\build_offline_bundle.ps1"
Write-Host ""
Write-Host "或直接拷貝 $Output 與 SF 專案到 USB, 不打包 zip 也行。"
