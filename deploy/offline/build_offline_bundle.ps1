<#
.SYNOPSIS
    [外網執行] 下載所有 SF 主機需要的套件, 打包成離線 bundle。
.DESCRIPTION
    跑在 IT 個人電腦 / 有 Internet 的工作站 / 跳板機。
    下載完打包成 zip, 透過 USB / 安全傳檔通道帶進內網。

    下載清單 (全部 Microsoft / 開源, 無授權問題):
    1. Visual C++ Redistributable 2015-2022
    2. SQL Server 2022 Express (Offline Installer ~250 MB)
    3. SQL Command Line Utilities
    4. URL Rewrite Module
    5. Application Request Routing (ARR)
    6. Python 3.11.x
    7. NSSM (Windows Service wrapper)
    8. Python wheels (從 requirements.txt 下載)

    完成後輸出: sf_offline_bundle_YYYYMMDD.zip (~600 MB)
.PARAMETER OutputDir
    打包輸出目錄, 預設 .\bundle_output。
.PARAMETER SkipPython
    跳過 Python 套件下載 (debug 用)。
.PARAMETER PythonVersion
    Python 版本, 預設 3.11.9。
.EXAMPLE
    .\build_offline_bundle.ps1
.EXAMPLE
    .\build_offline_bundle.ps1 -OutputDir D:\bundles
#>
[CmdletBinding()]
param(
    [string]$OutputDir = (Join-Path $PSScriptRoot 'bundle_output'),
    [string]$PythonVersion = '3.11.9',
    [switch]$SkipPython
)

$ErrorActionPreference = 'Stop'
$ts = Get-Date -Format 'yyyyMMdd_HHmmss'

# 目錄結構
$workDir = Join-Path $OutputDir "sf_offline_$ts"
$installersDir = Join-Path $workDir 'installers'
$wheelsDir = Join-Path $workDir 'python_wheels'
$scriptsDir = Join-Path $workDir 'scripts'

foreach ($d in @($workDir, $installersDir, $wheelsDir, $scriptsDir)) {
    if (-not (Test-Path $d)) { New-Item -Path $d -ItemType Directory -Force | Out-Null }
}

Write-Host "`n=== SF 離線 bundle 建構器 ===" -ForegroundColor Cyan
Write-Host "輸出目錄: $workDir`n"

# ===== 下載清單 =====
$downloads = @(
    @{
        Name = 'Visual C++ Redistributable x64'
        Url  = 'https://aka.ms/vs/17/release/vc_redist.x64.exe'
        Dest = 'vc_redist.x64.exe'
        Size = '~25 MB'
    },
    @{
        Name = 'SQL Server 2022 Express SSEI downloader'
        Url  = 'https://download.microsoft.com/download/5/1/4/5145fe04-4d30-4b85-b0d1-39533663a2f1/SQL2022-SSEI-Expr.exe'
        Dest = 'SQL2022-SSEI-Expr.exe'
        Size = '~5 MB (downloader)'
        Note = '下載後自動跑 ACTION=Download 抓完整 250 MB 離線版'
        PostDownload = 'SQLExpressFullDownload'
    },
    @{
        Name = 'SQL Server Command Line Utilities (sqlcmd)'
        Url  = 'https://go.microsoft.com/fwlink/?linkid=2240795'
        Dest = 'MsSqlCmdLnUtils.msi'
        Size = '~6 MB'
    },
    @{
        Name = 'URL Rewrite Module 2.1'
        Url  = 'https://download.microsoft.com/download/1/2/8/128E2E22-C1B9-44A4-BE2A-5859ED1D4592/rewrite_amd64_en-US.msi'
        Dest = 'rewrite_amd64_en-US.msi'
        Size = '~7 MB'
    },
    @{
        Name = 'Application Request Routing 3.0'
        Url  = 'https://download.microsoft.com/download/E/9/8/E9849D6A-020E-47E4-9FD0-A023E99B54EB/requestRouter_amd64.msi'
        Dest = 'requestRouter_amd64.msi'
        Size = '~7 MB'
    },
    @{
        Name = "Python $PythonVersion"
        Url  = "https://www.python.org/ftp/python/$PythonVersion/python-$PythonVersion-amd64.exe"
        Dest = "python-$PythonVersion-amd64.exe"
        Size = '~25 MB'
    },
    @{
        Name = 'NSSM 2.24 (zip)'
        Url  = 'https://nssm.cc/release/nssm-2.24.zip'
        Dest = 'nssm-2.24.zip'
        Size = '~400 KB'
    }
)

# ===== 下載 =====
Write-Host "===== Step 1: 下載 Microsoft / 開源套件 =====" -ForegroundColor Yellow
foreach ($item in $downloads) {
    $destPath = Join-Path $installersDir $item.Dest
    Write-Host ""
    Write-Host "[下載] $($item.Name) ($($item.Size))" -ForegroundColor Cyan
    Write-Host "  URL : $($item.Url)"
    Write-Host "  Dest: $destPath"

    if (Test-Path $destPath) {
        Write-Host "  [skip] 檔案已存在" -ForegroundColor DarkGray
        continue
    }

    try {
        $ProgressPreference = 'Continue'
        Invoke-WebRequest -Uri $item.Url -OutFile $destPath -UseBasicParsing
        $size = (Get-Item $destPath).Length / 1MB
        Write-Host ("  [ok  ] {0:N1} MB" -f $size) -ForegroundColor Green
    } catch {
        Write-Host "  [FAIL] $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  → 請手動下載到 $destPath" -ForegroundColor Yellow
    }

    if ($item.Note) {
        Write-Host "  注意: $($item.Note)" -ForegroundColor Yellow
    }

    # 處理 PostDownload: 自動跑 SSEI 抓完整離線版
    if ($item.PostDownload -eq 'SQLExpressFullDownload') {
        $fullExpr = Join-Path $installersDir 'SQLEXPR_x64_ENU.exe'
        if (Test-Path $fullExpr) {
            Write-Host "  [skip] 完整離線版已存在 $fullExpr" -ForegroundColor DarkGray
        } else {
            Write-Host "  → 跑 SSEI 抓 SQL Express 完整離線版 (~250 MB)..." -ForegroundColor Cyan
            try {
                $ssiArgs = @(
                    '/ACTION=Download',
                    '/MEDIATYPE=Core',
                    "/MEDIAPATH=$installersDir",
                    '/QUIET'
                )
                & $destPath @ssiArgs
                if ($LASTEXITCODE -eq 0 -and (Test-Path $fullExpr)) {
                    $size = (Get-Item $fullExpr).Length / 1MB
                    Write-Host ("  [ok  ] 完整離線版 {0:N0} MB" -f $size) -ForegroundColor Green
                } else {
                    Write-Host "  [FAIL] SSEI 完整版下載失敗, USB 將不是離線版!" -ForegroundColor Red
                    Write-Host "         請手動下載 SQLEXPR_x64_ENU.exe 放到 $installersDir" -ForegroundColor Red
                    exit 1
                }
            } catch {
                Write-Host "  [FAIL] SSEI 執行失敗: $_" -ForegroundColor Red
                exit 1
            }
        }

        # 刪除 SSEI downloader — USB 上不需要它 (它要連網才能用, 帶進內網沒用)
        if (Test-Path $destPath) {
            Remove-Item $destPath -Force
            Write-Host "  [clean] 已移除 SSEI downloader (USB 不需要, 只留完整離線版)" -ForegroundColor Yellow
        }
    }
}

# ===== Python wheels =====
if (-not $SkipPython) {
    Write-Host "`n===== Step 2: 下載 Python 套件 wheels =====" -ForegroundColor Yellow

    # 建立 requirements.txt
    $requirements = @"
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
    $reqPath = Join-Path $workDir 'requirements.txt'
    Set-Content -Path $reqPath -Value $requirements -Encoding UTF8

    # 需要本機 Python 才能下載 wheels (用本機 pip download)
    $localPython = Get-Command python -ErrorAction SilentlyContinue
    if (-not $localPython) {
        Write-Host "[WARN] 本機沒有 Python, 跳過 wheels 下載" -ForegroundColor Yellow
        Write-Host "  → 請手動在另一台有 Python 的環境跑:" -ForegroundColor Yellow
        Write-Host "    pip download -r requirements.txt -d $wheelsDir --platform win_amd64 --python-version 311 --only-binary=:all:" -ForegroundColor Yellow
    } else {
        Write-Host "用本機 Python 下載 wheels (Windows x64, Python 3.11)..."
        try {
            & python -m pip download -r $reqPath -d $wheelsDir `
                --platform win_amd64 `
                --python-version 311 `
                --only-binary=:all: `
                --no-cache-dir 2>&1 | Tee-Object -Variable pipOutput
            $count = (Get-ChildItem $wheelsDir -Filter '*.whl' -ErrorAction SilentlyContinue).Count
            Write-Host "[ok  ] 下載 $count 個 wheel 檔" -ForegroundColor Green
        } catch {
            Write-Host "[FAIL] pip download 失敗" -ForegroundColor Red
        }
    }
}

# ===== 複製 deploy 與 scripts =====
Write-Host "`n===== Step 3: 複製 SF 部署腳本到 bundle =====" -ForegroundColor Yellow
$sfRoot = Split-Path $PSScriptRoot -Parent | Split-Path -Parent  # 回到 C:\ClaudeHome\SFTP
if (Test-Path $sfRoot) {
    foreach ($subdir in @('deploy', 'scripts', 'config', 'sql', 'portal', 'docs')) {
        $src = Join-Path $sfRoot $subdir
        if (Test-Path $src) {
            $dst = Join-Path $workDir $subdir
            Copy-Item $src $dst -Recurse -Force
            Write-Host "  [ok  ] 複製 $subdir"
        }
    }
}

# ===== 產生 README =====
Write-Host "`n===== Step 4: 產生 bundle README =====" -ForegroundColor Yellow
$readmeContent = @"
# SF 離線安裝 Bundle

打包時間: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

## 內容

- ``installers/`` Microsoft 與第三方套件安裝檔
- ``python_wheels/`` Python 套件 (whl 檔)
- ``deploy/`` 部署 PowerShell 腳本 (00~17)
- ``scripts/`` 維運腳本 (tail_log / health_check / debug_bundle)
- ``config/`` 設定範本 (sshd_config, web.config)
- ``sql/`` SQL Schema
- ``portal/`` Flask Portal 程式碼骨架
- ``docs/`` 文件 (plan, mockup, architecture)
- ``requirements.txt`` Python 套件清單
- ``install_offline.ps1`` **一鍵安裝主腳本** (在 SF 主機跑)

## 部署步驟

1. 把整個 bundle 帶進公司內網 (USB / 安全傳檔)
2. 解壓到 SF 主機 ``C:\ClaudeHome\SFTP\``
3. 以**管理員**開 PowerShell 跑:

   ``.\install_offline.ps1``

   或 (若已申請公司 DB, 跳過本機 SQL):

   ``.\install_offline.ps1 -UseCorpDB -CorpDBServer "corp-sql01.internal"``

4. 全自動安裝完畢後驗證:

   ``.\scripts\health_check.ps1``

## 套件大小 (參考)

| 項目 | 大小 |
|------|------|
| installers/ | ~500 MB |
| python_wheels/ | ~80 MB |
| 程式碼 / 文件 | ~5 MB |
| **總計** | **~600 MB** |
"@
Set-Content -Path (Join-Path $workDir 'README.md') -Value $readmeContent -Encoding UTF8

# ===== 複製 install_offline.ps1 (主腳本) =====
$installScript = Join-Path $PSScriptRoot 'install_offline.ps1'
if (Test-Path $installScript) {
    Copy-Item $installScript (Join-Path $workDir 'install_offline.ps1') -Force
    Write-Host "  [ok  ] 複製 install_offline.ps1"
}

# ===== 產生 checksum + manifest =====
Write-Host "`n===== Step 5: 產生 checksum + manifest =====" -ForegroundColor Yellow

$manifest = @{
    bundle_name = "sf_offline_$ts"
    built_at = (Get-Date).ToString('o')
    built_by = "$env:USERDOMAIN\$env:USERNAME"
    built_on = $env:COMPUTERNAME
    files = @()
}

$allFiles = Get-ChildItem $workDir -File -Recurse
$totalSize = 0
foreach ($f in $allFiles) {
    $hash = (Get-FileHash $f.FullName -Algorithm SHA256).Hash
    $relPath = $f.FullName.Substring($workDir.Length + 1)
    $manifest.files += @{
        path = $relPath
        size = $f.Length
        sha256 = $hash
    }
    $totalSize += $f.Length
}

$manifest | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $workDir 'manifest.json') -Encoding UTF8
Write-Host "[ok  ] manifest.json (含 $($allFiles.Count) 個檔案的 SHA256)" -ForegroundColor Green

# 產生使用者讀的 INSTALL.txt
$installTxt = @"
============================================================
 SF 中繼檔案交換主機 - 離線安裝包
============================================================

打包時間: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
包大小  : $([math]::Round($totalSize / 1MB, 1)) MB
檔案數  : $($allFiles.Count)

------------------------------------------------------------
 三步驟部署 (預估 30-60 分鐘)
------------------------------------------------------------

[1] 把這個 USB / zip 在 SF 主機 解壓到:
    C:\ClaudeHome\SFTP\

[2] 以「管理員」身分開 PowerShell, 跑驗證:
    cd C:\ClaudeHome\SFTP\scripts
    .\verify_bundle.ps1

    應該看到所有檔案 [OK], 沒有 [FAIL] 或 [MISSING]

[3] 跑一鍵安裝:
    cd C:\ClaudeHome\SFTP\deploy\offline
    .\install_offline.ps1                  # 第一階段 (SQL Express)
    .\install_offline.ps1 -DbMode CorpDB ` # 第二階段 (公司 DB)
       -CorpDBServer 'corp-sql01.internal,1433'

------------------------------------------------------------
 內容
------------------------------------------------------------

installers/      Microsoft 與第三方安裝檔
python_wheels/   Python 套件 (whl)
deploy/          18 支部署腳本 (00~17)
scripts/         維運腳本 (tail_log/health_check/debug_bundle)
config/          設定範本
sql/             AuditLog Schema
portal/          Flask Portal 程式碼
docs/            文件 (mockup / SOP / 套件清單)
manifest.json    完整檔案清單 + SHA256
INSTALL.txt      本檔
README.md        bundle 說明

------------------------------------------------------------
 完整性驗證
------------------------------------------------------------

進入 SF 主機後, 跑:
    .\scripts\verify_bundle.ps1

腳本會比對每個檔案的 SHA256 與 manifest.json, 確保沒缺檔 / 沒被破壞。

------------------------------------------------------------
 若有問題
------------------------------------------------------------

1. 看部署 SOP:    docs\deployment_sop.md
2. 健康檢查:      .\scripts\health_check.ps1
3. 即時 log:      .\scripts\tail_log.ps1

============================================================
"@
Set-Content -Path (Join-Path $workDir 'INSTALL.txt') -Value $installTxt -Encoding UTF8
Write-Host "[ok  ] INSTALL.txt" -ForegroundColor Green

# ===== 打包 zip =====
Write-Host "`n===== Step 6: 打包成 zip =====" -ForegroundColor Yellow
$zipPath = Join-Path $OutputDir "sf_offline_bundle_$ts.zip"
Compress-Archive -Path "$workDir\*" -DestinationPath $zipPath -Force
$zipSize = (Get-Item $zipPath).Length / 1MB
Write-Host "[ok  ] $zipPath ($([math]::Round($zipSize, 1)) MB)" -ForegroundColor Green

# 產生 zip 的 SHA256
$zipHash = (Get-FileHash $zipPath -Algorithm SHA256).Hash
$hashPath = "$zipPath.sha256"
Set-Content -Path $hashPath -Value "$zipHash  $(Split-Path $zipPath -Leaf)" -Encoding ASCII
Write-Host "[ok  ] zip SHA256: $zipHash" -ForegroundColor Green
Write-Host "       已寫入: $hashPath" -ForegroundColor DarkGray

# ===== 完成 =====
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " 打包完成" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "輸出檔: $zipPath"
Write-Host "大小  : $([math]::Round($zipSize, 1)) MB"
Write-Host ""
Write-Host "下一步:"
Write-Host "  1. 把 zip 用 USB / 公司安全傳檔通道帶進內網"
Write-Host "  2. 在 SF 主機解壓到 C:\ClaudeHome\SFTP\"
Write-Host "  3. 以管理員開 PowerShell 跑 .\install_offline.ps1"
