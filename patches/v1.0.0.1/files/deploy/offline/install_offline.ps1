<#
.SYNOPSIS
    [SF 主機 一鍵離線安裝] 從 bundle 把所有東西自動裝起來, 不需 Internet。
.DESCRIPTION
    從 build_offline_bundle.ps1 產生的 bundle 全自動安裝:
    1. Visual C++ Redistributable
    2. SQL Server 2022 Express (預設, 第一階段) 或 跳過 (第二階段走公司 DB)
    3. sqlcmd / URL Rewrite / ARR
    4. Python + NSSM
    5. Windows Features (OpenSSH/IIS/FSRM/Backup/RSAT)
    6. Python 套件 (從本地 wheels)
    7. 依序跑 deploy\00 ~ 17 設定腳本

    雙模式:
    - 第一階段 (預設): -DbMode Express → 裝 SQL Server 2022 Express 在 SF 本機
    - 第二階段        : -DbMode CorpDB  → 跳過 SQL 安裝, 連公司 DB Server

    全程支援 -DryRun 預演。
.PARAMETER BundleDir
    bundle 根目錄, 預設當前目錄。
.PARAMETER DbMode
    Express (第一階段) 或 CorpDB (第二階段)。預設 Express。
.PARAMETER CorpDBServer
    公司 DB Server 連線字串, DbMode=CorpDB 時必填, 例: 'corp-sql01.internal,1433'
.PARAMETER CorpDBName
    DB 名稱, 預設 'FileExchangeAudit'
.PARAMETER SkipFeatures
    跳過 Windows Features 安裝 (假設已裝好)。
.PARAMETER SkipPython
    跳過 Python + pip install。
.PARAMETER SkipDeployScripts
    只裝套件, 不跑 deploy/00~17。
.PARAMETER DryRun
    只列出將執行的動作。
.EXAMPLE
    # 第一階段 (預設, SQL Express)
    .\install_offline.ps1
.EXAMPLE
    # 第二階段 (公司 DB)
    .\install_offline.ps1 -DbMode CorpDB -CorpDBServer 'corp-sql01.internal,1433'
.EXAMPLE
    # 預演 (不實際安裝)
    .\install_offline.ps1 -DryRun
#>
[CmdletBinding()]
param(
    [string]$BundleDir = $PSScriptRoot,
    [ValidateSet('Express', 'CorpDB')]
    [string]$DbMode = 'Express',
    [string]$CorpDBServer,
    [string]$CorpDBName = 'FileExchangeAudit',
    [switch]$SkipFeatures,
    [switch]$SkipPython,
    [switch]$SkipDeployScripts,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$startTime = Get-Date

function Step {
    param([int]$Num, [string]$Title)
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host (" Step {0:D2}: {1}" -f $Num, $Title) -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Cyan
}

function RunCmd {
    param([string]$Cmd, [string[]]$Args, [string]$Description)
    Write-Host "[exec] $Description"
    Write-Host "       $Cmd $($Args -join ' ')" -ForegroundColor DarkGray

    if ($DryRun) { Write-Host "       (dry-run)" -ForegroundColor Yellow; return 0 }

    & $Cmd @Args
    $code = $LASTEXITCODE
    if ($code -ne 0 -and $code -ne $null) {
        Write-Host "       [warn] exit code $code" -ForegroundColor Yellow
    } else {
        Write-Host "       [ok]" -ForegroundColor Green
    }
    return $code
}

# ===== Step 0: 前置檢查 =====
Step 0 "前置檢查"

# 管理員權限
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrators')
if (-not $isAdmin) {
    Write-Host "[FAIL] 必須以管理員身分執行" -ForegroundColor Red
    exit 1
}
Write-Host "[ok] 管理員權限"

# bundle 完整性 — 自動偵測 installers 位置
$installersDir = Join-Path $BundleDir 'installers'
$wheelsDir = Join-Path $BundleDir 'python_wheels'

# 若 BundleDir 下沒 installers/, 嘗試 sf_binaries/ 子目錄 (fetch_binaries_win11.ps1 的結構)
if (-not (Test-Path $installersDir)) {
    $altInstallers = Join-Path $BundleDir 'sf_binaries\installers'
    $altWheels = Join-Path $BundleDir 'sf_binaries\python_wheels'
    if (Test-Path $altInstallers) {
        Write-Host "[info] 偵測到 sf_binaries/ 子目錄結構, 自動切換路徑" -ForegroundColor Cyan
        $installersDir = $altInstallers
        $wheelsDir = $altWheels
    }
}

# deploy/ 目錄 — 若 BundleDir 是 deploy/offline/, 退一級
$deployDir = Join-Path $BundleDir 'deploy'
if (-not (Test-Path $deployDir)) {
    $altDeploy = Join-Path (Split-Path $BundleDir -Parent) '.'   # 退一層
    $altDeploy2 = Split-Path $BundleDir -Parent                  # 退一層 (deploy/offline 退到 deploy)
    if (Test-Path (Join-Path $altDeploy2 '00_check_prereqs.ps1')) {
        $deployDir = $altDeploy2
        Write-Host "[info] deploy/ 偵測到上一層: $deployDir" -ForegroundColor Cyan
    }
}

if (-not (Test-Path $installersDir)) {
    Write-Host "[FAIL] 找不到 installers 目錄" -ForegroundColor Red
    Write-Host "  嘗試了:" -ForegroundColor Yellow
    Write-Host "    $BundleDir\installers"
    Write-Host "    $BundleDir\sf_binaries\installers"
    Write-Host "  解法: 跑 install_offline.ps1 前先把 installers / python_wheels 搬到 BundleDir 根目錄" -ForegroundColor Yellow
    exit 1
}
Write-Host "[ok] bundle 結構正常"
Write-Host "     installers: $installersDir"
Write-Host "     wheels:     $wheelsDir"
Write-Host "     deploy:     $deployDir"

# DbMode 檢查
if ($DbMode -eq 'CorpDB' -and -not $CorpDBServer) {
    Write-Host "[FAIL] DbMode=CorpDB 必須提供 -CorpDBServer" -ForegroundColor Red
    exit 1
}
Write-Host "[ok] DB 模式: $DbMode" -ForegroundColor Green
if ($DbMode -eq 'CorpDB') {
    Write-Host "      → 跳過本機 SQL Express, 將連: $CorpDBServer / $CorpDBName" -ForegroundColor Yellow
}

# ===== Step 1: Visual C++ Redistributable =====
Step 1 "Visual C++ Redistributable 2015-2022"
$vcExe = Join-Path $installersDir 'vc_redist.x64.exe'
if (Test-Path $vcExe) {
    RunCmd -Cmd $vcExe -Args @('/install', '/quiet', '/norestart') -Description "Install VC++ Redistributable"
} else {
    Write-Host "[skip] $vcExe 不存在" -ForegroundColor Yellow
}

# ===== Step 2: SQL Server (依模式) =====
if ($DbMode -eq 'Express') {
    Step 2 "SQL Server 2022 Express (第一階段)"
    # 接受任何語系: ENU (English) / CHT (繁中) / CHS (簡中) / JPN 等
    $sqlExpr = $null
    foreach ($lang in @('ENU', 'CHT', 'CHS', 'JPN', 'KOR', 'DEU', 'FRA')) {
        $candidate = Join-Path $installersDir "SQLEXPR_x64_$lang.exe"
        if (Test-Path $candidate) {
            $sqlExpr = $candidate
            Write-Host "[info] 偵測到 SQL Express 完整離線版: SQLEXPR_x64_$lang.exe" -ForegroundColor Cyan
            break
        }
    }
    $sqlSsei = Join-Path $installersDir 'SQL2022-SSEI-Expr.exe'

    if ($sqlExpr) {
        # 完整離線版 (250 MB), 可純離線安裝
        $sqlArgs = @(
            '/Q',
            '/ACTION=Install',
            '/FEATURES=SQLEngine',
            '/INSTANCENAME=SQLEXPRESS',
            '/SQLSVCACCOUNT=NT AUTHORITY\NetworkService',
            '/SQLSYSADMINACCOUNTS=BUILTIN\Administrators',
            '/AGTSVCACCOUNT=NT AUTHORITY\NetworkService',
            '/TCPENABLED=1',
            '/IACCEPTSQLSERVERLICENSETERMS'
        )
        RunCmd -Cmd $sqlExpr -Args $sqlArgs -Description "Install SQL Express (silent, 完整離線版)"
    } else {
        # 沒有完整離線版 — 內網絕對不能跑 SSEI (它要連網)
        Write-Host "[FAIL] 找不到 SQL Express 完整離線版 SQLEXPR_x64_ENU.exe" -ForegroundColor Red
        Write-Host ""
        Write-Host "  USB / bundle 應該包含完整離線版 (~250 MB), 不是 SSEI downloader (~5 MB)" -ForegroundColor Yellow
        Write-Host "  解法:" -ForegroundColor Yellow
        Write-Host "    1. 回外網工作站重跑 build_offline_bundle.ps1, 確認下載完整版"
        Write-Host "    2. 或手動下載 SQLEXPR_x64_ENU.exe 拷貝到:"
        Write-Host "       $installersDir\"
        if (Test-Path $sqlSsei) {
            Write-Host ""
            Write-Host "  ⚠️ 偵測到 SSEI downloader, 但內網沒辦法用它 (它要連網抓完整版)" -ForegroundColor Yellow
        }
        Write-Host ""
        Write-Host "  → 跳過 SQL Express 安裝 (DB 部分不會完成, 其他套件繼續裝)" -ForegroundColor Yellow
    }
} else {
    Step 2 "SQL Server (第二階段 公司 DB)"
    Write-Host "[skip] 跳過本機 SQL 安裝 (將使用 $CorpDBServer)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  確認:"
    Write-Host "  - 公司 DB Instance 已開好"
    Write-Host "  - DB '$CorpDBName' 已建立 (DBA 那邊)"
    Write-Host "  - SF 主機 → $CorpDBServer 防火牆 TCP 1433 已通"
    Write-Host "  - SF 機器帳號或服務帳號有 db_datareader + db_datawriter 權限"
}

# ===== Step 3: SQL Command Line Utilities (sqlcmd) =====
Step 3 "SQL Command Line Utilities (sqlcmd)"
$sqlCmdMsi = Join-Path $installersDir 'MsSqlCmdLnUtils.msi'
if (Test-Path $sqlCmdMsi) {
    RunCmd -Cmd 'msiexec.exe' -Args @('/i', $sqlCmdMsi, '/quiet', '/norestart', 'IACCEPTMSSQLCMDLNUTILSLICENSETERMS=YES') -Description "Install sqlcmd"
} else {
    Write-Host "[skip] sqlcmd installer 不存在" -ForegroundColor Yellow
}

# ===== Step 4: URL Rewrite + ARR =====
Step 4 "URL Rewrite + Application Request Routing"
$urlRewrite = Join-Path $installersDir 'rewrite_amd64_en-US.msi'
$arr = Join-Path $installersDir 'requestRouter_amd64.msi'

if (Test-Path $urlRewrite) {
    RunCmd -Cmd 'msiexec.exe' -Args @('/i', $urlRewrite, '/quiet', '/norestart') -Description "Install URL Rewrite"
}
if (Test-Path $arr) {
    RunCmd -Cmd 'msiexec.exe' -Args @('/i', $arr, '/quiet', '/norestart') -Description "Install ARR"
}

# ===== Step 5: Python =====
if (-not $SkipPython) {
    Step 5 "Python 3.11"
    $pythonExe = Get-ChildItem $installersDir -Filter 'python-*-amd64.exe' | Select-Object -First 1
    if ($pythonExe) {
        RunCmd -Cmd $pythonExe.FullName -Args @(
            '/quiet',
            'InstallAllUsers=1',
            'PrependPath=1',
            'Include_test=0',
            'Include_doc=0',
            'Include_dev=0'
        ) -Description "Install Python (silent, all users, PATH)"

        # 重整 PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                    [System.Environment]::GetEnvironmentVariable('Path', 'User')
    } else {
        Write-Host "[skip] python-*-amd64.exe 不存在" -ForegroundColor Yellow
    }
}

# ===== Step 6: NSSM =====
Step 6 "NSSM (Windows Service wrapper)"
$nssmZip = Join-Path $installersDir 'nssm-2.24.zip'
$nssmDir = 'C:\Tools\nssm'
if (Test-Path $nssmZip) {
    if (-not (Test-Path $nssmDir)) { New-Item -Path $nssmDir -ItemType Directory -Force | Out-Null }
    if (-not $DryRun) {
        Expand-Archive -Path $nssmZip -DestinationPath $nssmDir -Force
        # 把 nssm.exe (win64) 複製到 C:\Tools\
        $nssmExe = Get-ChildItem $nssmDir -Filter 'nssm.exe' -Recurse | Where-Object { $_.FullName -like '*win64*' } | Select-Object -First 1
        if ($nssmExe) {
            Copy-Item $nssmExe.FullName 'C:\Tools\nssm.exe' -Force
            Write-Host "[ok] NSSM 解壓至 $nssmDir, 主程式 C:\Tools\nssm.exe" -ForegroundColor Green
        }
    }
} else {
    Write-Host "[skip] nssm-2.24.zip 不存在" -ForegroundColor Yellow
}

# ===== Step 7: Windows Features =====
if (-not $SkipFeatures) {
    Step 7 "Windows Features (IIS / FTP / FSRM / Backup / RSAT)"

    $features = @(
        'Web-Server', 'Web-WebServer', 'Web-Common-Http', 'Web-Static-Content',
        'Web-Default-Doc', 'Web-Http-Errors', 'Web-Http-Logging', 'Web-Custom-Logging',
        'Web-Request-Monitor', 'Web-Security', 'Web-Filtering', 'Web-Performance',
        'Web-Mgmt-Console',
        'Web-Ftp-Server',
        'FS-Resource-Manager',
        'Windows-Server-Backup',
        'RSAT-AD-PowerShell',
        'NET-Framework-45-Features'
    )

    foreach ($f in $features) {
        $st = Get-WindowsFeature -Name $f -ErrorAction SilentlyContinue
        if ($st -and $st.InstallState -ne 'Installed') {
            if ($DryRun) {
                Write-Host "[dry] Install $f"
            } else {
                Write-Host "[exec] Install-WindowsFeature $f"
                Install-WindowsFeature -Name $f -IncludeManagementTools -WarningAction SilentlyContinue | Out-Null
            }
        } else {
            Write-Host "[skip] $f 已安裝"
        }
    }

    # OpenSSH (capability)
    $sshCap = Get-WindowsCapability -Online -Name 'OpenSSH.Server*' -ErrorAction SilentlyContinue
    if ($sshCap -and $sshCap.State -ne 'Installed') {
        if ($DryRun) {
            Write-Host "[dry] Add-WindowsCapability OpenSSH.Server"
        } else {
            Write-Host "[exec] Add OpenSSH.Server capability"
            Add-WindowsCapability -Online -Name $sshCap.Name | Out-Null
        }
    } else {
        Write-Host "[skip] OpenSSH.Server 已安裝"
    }
}

# ===== Step 8: Python 套件 =====
if (-not $SkipPython) {
    Step 8 "Python 套件 (pip install --no-index --find-links)"

    $reqPath = Join-Path $BundleDir 'requirements.txt'
    if ((Test-Path $reqPath) -and (Test-Path $wheelsDir)) {
        $pip = Get-Command pip -ErrorAction SilentlyContinue
        if ($pip) {
            RunCmd -Cmd 'pip' -Args @(
                'install', '--no-index',
                '--find-links', $wheelsDir,
                '-r', $reqPath
            ) -Description "Install Python packages from local wheels"
        } else {
            Write-Host "[FAIL] 找不到 pip (Python 安裝可能失敗)" -ForegroundColor Red
        }
    } else {
        Write-Host "[skip] requirements.txt 或 python_wheels 不存在" -ForegroundColor Yellow
    }
}

# ===== Step 9: 依序跑 deploy/00 ~ 17 =====
if (-not $SkipDeployScripts) {
    Step 9 "執行 deploy/00 ~ 17 設定腳本"

    if (-not (Test-Path $deployDir)) {
        Write-Host "[skip] deploy 目錄不存在: $deployDir" -ForegroundColor Yellow
    } else {
        $scripts = Get-ChildItem $deployDir -Filter '*.ps1' | Sort-Object Name
        foreach ($s in $scripts) {
            # 第二階段時跳過 08 (SQL Express setup)
            if ($DbMode -eq 'CorpDB' -and $s.Name -like '08_*sql*') {
                Write-Host "[skip] $($s.Name) (CorpDB 模式)" -ForegroundColor Yellow
                continue
            }

            Write-Host ""
            Write-Host "→ 執行 $($s.Name)" -ForegroundColor Cyan
            if ($DryRun) {
                Write-Host "  (dry-run)" -ForegroundColor Yellow
            } else {
                try {
                    & $s.FullName
                } catch {
                    Write-Host "  [warn] $($s.Name) 異常: $_" -ForegroundColor Yellow
                }
            }
        }
    }
}

# ===== Step 10: 寫入 DB 連線設定 =====
Step 10 "Portal DB 連線設定"

$appSettings = 'D:\_portal\app\appsettings.json'
$connString = if ($DbMode -eq 'Express') {
    'Server=.\SQLEXPRESS;Database=FileExchangeAudit;Integrated Security=True;TrustServerCertificate=True'
} else {
    "Server=$CorpDBServer;Database=$CorpDBName;Integrated Security=True;TrustServerCertificate=True"
}

if (-not $DryRun -and (Test-Path 'D:\_portal\app')) {
    $config = @{
        DbMode = $DbMode
        ConnectionString = $connString
        DbServer = if ($DbMode -eq 'CorpDB') { $CorpDBServer } else { '.\SQLEXPRESS' }
        DbName = $CorpDBName
        InstalledAt = (Get-Date).ToString('o')
    }
    $config | ConvertTo-Json | Set-Content -Path $appSettings -Encoding UTF8
    Write-Host "[ok] 寫入 $appSettings" -ForegroundColor Green
    Write-Host "     DB Mode: $DbMode"
    Write-Host "     Connection: $connString"
} else {
    Write-Host "[skip] (dry-run 或 Portal 目錄未建立)" -ForegroundColor Yellow
}

# ===== 完成 =====
$elapsed = (Get-Date) - $startTime
Write-Host ""
Write-Host ("=" * 60) -ForegroundColor Green
Write-Host " 一鍵安裝完成" -ForegroundColor Green
Write-Host ("=" * 60) -ForegroundColor Green
Write-Host "DB 模式: $DbMode"
Write-Host "耗時:    $($elapsed.ToString('mm\:ss'))"
Write-Host ""
Write-Host "下一步:"
Write-Host "  1. 跑健康檢查:  .\scripts\health_check.ps1"
Write-Host "  2. 啟動 Portal: Start-Service FileExchangePortal"
Write-Host "  3. 開啟瀏覽器:  https://<host-name>/"
Write-Host ""
if ($DbMode -eq 'Express') {
    Write-Host "第二階段 (改用公司 DB) 時, 跑:" -ForegroundColor Yellow
    Write-Host "  .\migrate_db_to_corp.ps1 -CorpDBServer '<server>' -CorpDBName '<db>'" -ForegroundColor Yellow
}
