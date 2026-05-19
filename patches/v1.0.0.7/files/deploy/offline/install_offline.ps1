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

    特色 (v1.0.0.3+):
    - **完全 idempotent**: 已裝的全部 skip, 可重複執行
    - **單步失敗不 abort**: 容錯 warn + 繼續, 結尾顯示 summary
    - **OpenSSH 失敗給明確 fallback**: 內網無 FoD source 時提示 GUI / WSUS / sxs 解法

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
    # 重跑 (已裝的都會 skip, idempotent)
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

# v1.0.0.3: 改成 Continue, 個別 step 用 try-catch 自行容錯
$ErrorActionPreference = 'Continue'
$startTime = Get-Date

# 紀錄每步結果, 結尾顯示 summary
$script:results = New-Object System.Collections.Generic.List[hashtable]

function Step {
    param([int]$Num, [string]$Title)
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host (" Step {0:D2}: {1}" -f $Num, $Title) -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Cyan
}

function RecordStep {
    param([string]$Name, [string]$Status, [string]$Detail = '')
    $script:results.Add(@{ name = $Name; status = $Status; detail = $Detail })
    $color = switch ($Status) {
        'ok'   { 'Green' }
        'skip' { 'DarkGray' }
        'warn' { 'Yellow' }
        'fail' { 'Red' }
        default { 'White' }
    }
    Write-Host ("[{0}] {1} {2}" -f $Status.PadRight(4), $Name, $Detail) -ForegroundColor $color
}

function RunCmd {
    param([string]$Cmd, [string[]]$Args, [string]$Description)
    Write-Host "[exec] $Description"
    Write-Host "       $Cmd $($Args -join ' ')" -ForegroundColor DarkGray

    if ($DryRun) { Write-Host "       (dry-run)" -ForegroundColor Yellow; return 0 }

    try {
        & $Cmd @Args
        $code = $LASTEXITCODE
        if ($code -ne 0 -and $code -ne $null) {
            Write-Host "       [warn] exit code $code" -ForegroundColor Yellow
            return $code
        } else {
            Write-Host "       [ok]" -ForegroundColor Green
            return 0
        }
    } catch {
        Write-Host "       [fail] $($_.Exception.Message)" -ForegroundColor Red
        return -1
    }
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

# 若 BundleDir 下沒 installers/, 嘗試 sf_binaries/ 子目錄
if (-not (Test-Path $installersDir)) {
    $altInstallers = Join-Path $BundleDir 'sf_binaries\installers'
    $altWheels = Join-Path $BundleDir 'sf_binaries\python_wheels'
    if (Test-Path $altInstallers) {
        Write-Host "[info] 偵測到 sf_binaries/ 子目錄結構, 自動切換路徑" -ForegroundColor Cyan
        $installersDir = $altInstallers
        $wheelsDir = $altWheels
    }
}

# deploy/ 目錄
$deployDir = Join-Path $BundleDir 'deploy'
if (-not (Test-Path $deployDir)) {
    $altDeploy2 = Split-Path $BundleDir -Parent
    if (Test-Path (Join-Path $altDeploy2 '00_check_prereqs.ps1')) {
        $deployDir = $altDeploy2
        Write-Host "[info] deploy/ 偵測到上一層: $deployDir" -ForegroundColor Cyan
    }
}

if (-not (Test-Path $installersDir)) {
    Write-Host "[FAIL] 找不到 installers 目錄" -ForegroundColor Red
    exit 1
}
Write-Host "[ok] bundle 結構正常"
Write-Host "     installers: $installersDir"
Write-Host "     wheels:     $wheelsDir"
Write-Host "     deploy:     $deployDir"

if ($DbMode -eq 'CorpDB' -and -not $CorpDBServer) {
    Write-Host "[FAIL] DbMode=CorpDB 必須提供 -CorpDBServer" -ForegroundColor Red
    exit 1
}
Write-Host "[ok] DB 模式: $DbMode" -ForegroundColor Green
if ($DbMode -eq 'CorpDB') {
    Write-Host "      → 跳過本機 SQL Express, 將連: $CorpDBServer / $CorpDBName" -ForegroundColor Yellow
}
RecordStep 'Step 0 前置檢查' 'ok'

# ===== Step 1: Visual C++ Redistributable =====
Step 1 "Visual C++ Redistributable 2015-2022"

# 已裝偵測: 檢查 registry
$vcInstalled = $false
try {
    $vcKey = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64' -ErrorAction Stop
    if ($vcKey.Installed -eq 1) {
        $vcVer = '{0}.{1}.{2}' -f $vcKey.Major, $vcKey.Minor, $vcKey.Bld
        $vcInstalled = $true
        RecordStep 'VC++ Redist' 'skip' "已安裝 $vcVer"
    }
} catch {}

if (-not $vcInstalled) {
    $vcExe = Join-Path $installersDir 'vc_redist.x64.exe'
    if (Test-Path $vcExe) {
        $rc = RunCmd -Cmd $vcExe -Args @('/install', '/quiet', '/norestart') -Description "Install VC++ Redistributable"
        if ($rc -eq 0) { RecordStep 'VC++ Redist' 'ok' '安裝完成' }
        else { RecordStep 'VC++ Redist' 'warn' "exit=$rc" }
    } else {
        RecordStep 'VC++ Redist' 'skip' "$vcExe 不存在"
    }
}

# ===== Step 2: SQL Server =====
if ($DbMode -eq 'Express') {
    Step 2 "SQL Server 2022 Express (第一階段)"

    # 已裝偵測: 檢查 service
    $sqlSvc = Get-Service -Name 'MSSQL$SQLEXPRESS' -ErrorAction SilentlyContinue
    if ($sqlSvc) {
        RecordStep 'SQL Express' 'skip' "已安裝, 狀態 $($sqlSvc.Status)"
    } else {
        $sqlExpr = $null
        foreach ($lang in @('ENU', 'CHT', 'CHS', 'JPN', 'KOR', 'DEU', 'FRA')) {
            $candidate = Join-Path $installersDir "SQLEXPR_x64_$lang.exe"
            if (Test-Path $candidate) {
                $sqlExpr = $candidate
                Write-Host "[info] 偵測到 SQL Express: SQLEXPR_x64_$lang.exe" -ForegroundColor Cyan
                break
            }
        }

        if ($sqlExpr) {
            $sqlArgs = @(
                '/Q', '/ACTION=Install', '/FEATURES=SQLEngine',
                '/INSTANCENAME=SQLEXPRESS',
                '/SQLSVCACCOUNT=NT AUTHORITY\NetworkService',
                '/SQLSYSADMINACCOUNTS=BUILTIN\Administrators',
                '/AGTSVCACCOUNT=NT AUTHORITY\NetworkService',
                '/TCPENABLED=1',
                '/IACCEPTSQLSERVERLICENSETERMS'
            )
            $rc = RunCmd -Cmd $sqlExpr -Args $sqlArgs -Description "Install SQL Express"
            if ($rc -eq 0) { RecordStep 'SQL Express' 'ok' '安裝完成' }
            else { RecordStep 'SQL Express' 'warn' "exit=$rc" }
        } else {
            Write-Host "[FAIL] 找不到 SQL Express 完整離線版" -ForegroundColor Red
            RecordStep 'SQL Express' 'fail' '找不到 installer'
        }
    }
} else {
    Step 2 "SQL Server (第二階段 公司 DB)"
    Write-Host "[skip] 跳過本機 SQL 安裝 (將使用 $CorpDBServer)" -ForegroundColor Yellow
    RecordStep 'SQL (CorpDB)' 'skip' "用 $CorpDBServer"
}

# ===== Step 3: sqlcmd =====
Step 3 "SQL Command Line Utilities (sqlcmd)"

$sqlcmdExisting = Get-Command sqlcmd.exe -ErrorAction SilentlyContinue
if ($sqlcmdExisting) {
    RecordStep 'sqlcmd' 'skip' "已安裝: $($sqlcmdExisting.Source)"
} else {
    $sqlCmdMsi = Join-Path $installersDir 'MsSqlCmdLnUtils.msi'
    if (Test-Path $sqlCmdMsi) {
        $rc = RunCmd -Cmd 'msiexec.exe' -Args @('/i', $sqlCmdMsi, '/quiet', '/norestart', 'IACCEPTMSSQLCMDLNUTILSLICENSETERMS=YES') -Description "Install sqlcmd"
        if ($rc -eq 0) { RecordStep 'sqlcmd' 'ok' '安裝完成' }
        else { RecordStep 'sqlcmd' 'warn' "exit=$rc" }
    } else {
        RecordStep 'sqlcmd' 'skip' 'installer 不存在'
    }
}

# ===== Step 4: URL Rewrite + ARR =====
Step 4 "URL Rewrite + Application Request Routing"

Import-Module WebAdministration -ErrorAction SilentlyContinue

$urlRewriteInstalled = $false
$arrInstalled = $false
try {
    $modules = Get-WebGlobalModule -ErrorAction Stop
    $urlRewriteInstalled = $null -ne ($modules | Where-Object { $_.Name -eq 'RewriteModule' })
    $arrInstalled = $null -ne ($modules | Where-Object { $_.Name -like 'ApplicationRequestRouting*' })
} catch {
    Write-Host "[warn] 無法讀 IIS module 清單 (IIS 可能未裝): $($_.Exception.Message)" -ForegroundColor Yellow
}

if ($urlRewriteInstalled) {
    RecordStep 'URL Rewrite' 'skip' '已安裝'
} else {
    $urlRewrite = Join-Path $installersDir 'rewrite_amd64_en-US.msi'
    if (Test-Path $urlRewrite) {
        $rc = RunCmd -Cmd 'msiexec.exe' -Args @('/i', $urlRewrite, '/quiet', '/norestart') -Description "Install URL Rewrite"
        if ($rc -eq 0) { RecordStep 'URL Rewrite' 'ok' '安裝完成' }
        else { RecordStep 'URL Rewrite' 'warn' "exit=$rc" }
    } else {
        RecordStep 'URL Rewrite' 'skip' 'installer 不存在'
    }
}

if ($arrInstalled) {
    RecordStep 'ARR' 'skip' '已安裝'
} else {
    $arr = Join-Path $installersDir 'requestRouter_amd64.msi'
    if (Test-Path $arr) {
        $rc = RunCmd -Cmd 'msiexec.exe' -Args @('/i', $arr, '/quiet', '/norestart') -Description "Install ARR"
        if ($rc -eq 0) { RecordStep 'ARR' 'ok' '安裝完成' }
        else { RecordStep 'ARR' 'warn' "exit=$rc" }
    } else {
        RecordStep 'ARR' 'skip' 'installer 不存在'
    }
}

# ===== Step 5: Python =====
if (-not $SkipPython) {
    Step 5 "Python 3.11"

    # 已裝偵測: 檢查典型路徑
    $pyPaths = @(
        "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe",
        "C:\Program Files\Python311\python.exe",
        "C:\Python311\python.exe"
    )
    $existingPy = $null
    foreach ($p in $pyPaths) {
        if (Test-Path $p) { $existingPy = $p; break }
    }

    if ($existingPy) {
        $pyVer = & $existingPy --version 2>&1
        RecordStep 'Python 3.11' 'skip' "已安裝: $existingPy ($pyVer)"
    } else {
        $pythonExe = Get-ChildItem $installersDir -Filter 'python-*-amd64.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($pythonExe) {
            $rc = RunCmd -Cmd $pythonExe.FullName -Args @(
                '/quiet', 'InstallAllUsers=1', 'PrependPath=1',
                'Include_test=0', 'Include_doc=0', 'Include_dev=0'
            ) -Description "Install Python (silent, all users, PATH)"

            # 重整 PATH
            $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                        [System.Environment]::GetEnvironmentVariable('Path', 'User')

            if ($rc -eq 0) { RecordStep 'Python 3.11' 'ok' '安裝完成' }
            else { RecordStep 'Python 3.11' 'warn' "exit=$rc" }
        } else {
            RecordStep 'Python 3.11' 'skip' "python-*-amd64.exe 不存在"
        }
    }
}

# ===== Step 6: NSSM =====
Step 6 "NSSM (Windows Service wrapper)"

$nssmTarget = 'C:\Tools\nssm.exe'
if (Test-Path $nssmTarget) {
    RecordStep 'NSSM' 'skip' "已存在: $nssmTarget"
} else {
    $nssmZip = Join-Path $installersDir 'nssm-2.24.zip'
    $nssmDir = 'C:\Tools\nssm'
    if (Test-Path $nssmZip) {
        if (-not (Test-Path $nssmDir)) { New-Item -Path $nssmDir -ItemType Directory -Force | Out-Null }
        if (-not (Test-Path 'C:\Tools')) { New-Item -Path 'C:\Tools' -ItemType Directory -Force | Out-Null }

        if ($DryRun) {
            Write-Host "[dry] Expand-Archive $nssmZip"
            RecordStep 'NSSM' 'skip' '(dry-run)'
        } else {
            try {
                Expand-Archive -Path $nssmZip -DestinationPath $nssmDir -Force
                $nssmExe = Get-ChildItem $nssmDir -Filter 'nssm.exe' -Recurse | Where-Object { $_.FullName -like '*win64*' } | Select-Object -First 1
                if ($nssmExe) {
                    Copy-Item $nssmExe.FullName $nssmTarget -Force
                    RecordStep 'NSSM' 'ok' "解壓至 $nssmDir + 主程式 $nssmTarget"
                } else {
                    RecordStep 'NSSM' 'warn' '解壓後找不到 win64/nssm.exe'
                }
            } catch {
                RecordStep 'NSSM' 'fail' $_.Exception.Message
            }
        }
    } else {
        RecordStep 'NSSM' 'skip' 'nssm-2.24.zip 不存在'
    }
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

    $featOk = 0; $featSkip = 0; $featFail = 0
    foreach ($f in $features) {
        $st = Get-WindowsFeature -Name $f -ErrorAction SilentlyContinue
        if (-not $st) {
            Write-Host "[skip] $f 不可用" -ForegroundColor DarkGray
            $featSkip++
            continue
        }
        if ($st.InstallState -eq 'Installed') {
            Write-Host "[skip] $f 已安裝" -ForegroundColor DarkGray
            $featSkip++
        } else {
            if ($DryRun) {
                Write-Host "[dry] Install $f"
                $featSkip++
            } else {
                Write-Host "[exec] Install-WindowsFeature $f"
                try {
                    Install-WindowsFeature -Name $f -IncludeManagementTools -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null
                    $featOk++
                } catch {
                    Write-Host "  [warn] $f 失敗: $($_.Exception.Message)" -ForegroundColor Yellow
                    $featFail++
                }
            }
        }
    }
    RecordStep 'Windows Features' 'ok' "新裝 $featOk, skip $featSkip, fail $featFail"

    # OpenSSH (capability OR portable) — 雙軌偵測 + try-catch 容錯
    # v1.0.0.7: 先看 sshd service 存在 (portable / FoD 通用), 避免重灌
    Write-Host ""
    Write-Host "--- OpenSSH Server ---"
    $sshdSvc = Get-Service -Name sshd -ErrorAction SilentlyContinue
    $sshCap = Get-WindowsCapability -Online -Name 'OpenSSH.Server*' -ErrorAction SilentlyContinue
    if ($sshdSvc) {
        # portable 或 FoD 已裝完, service 存在就算 ok
        $detectVia = if ($sshCap -and $sshCap.State -eq 'Installed') { 'FoD capability' } else { 'portable (Win32-OpenSSH)' }
        RecordStep 'OpenSSH.Server' 'skip' "已安裝 ($detectVia, sshd $($sshdSvc.Status))"
    } elseif ($sshCap -and $sshCap.State -eq 'Installed') {
        RecordStep 'OpenSSH.Server' 'skip' '已安裝 (capability)'
    } elseif (-not $sshCap) {
        RecordStep 'OpenSSH.Server' 'skip' 'capability 不存在 (Windows 版本可能不支援)'
    } else {
        if ($DryRun) {
            Write-Host "[dry] Add-WindowsCapability OpenSSH.Server"
            RecordStep 'OpenSSH.Server' 'skip' '(dry-run)'
        } else {
            Write-Host "[exec] Add OpenSSH.Server capability ($($sshCap.Name))"
            try {
                Add-WindowsCapability -Online -Name $sshCap.Name -ErrorAction Stop | Out-Null
                RecordStep 'OpenSSH.Server' 'ok' '安裝完成'
            } catch {
                Write-Host "  [FAIL] OpenSSH 安裝失敗: $($_.Exception.Message)" -ForegroundColor Red
                Write-Host ""
                Write-Host "  常見原因: 0x800f0907 = 內網無 Windows Update / FoD source" -ForegroundColor Yellow
                Write-Host "  解法 (建議照順序試):" -ForegroundColor Yellow
                Write-Host "    A. ⭐ Portable 路線 (推薦, 5 MB zip, 不需 FoD):"
                Write-Host "       外網抓 https://github.com/PowerShell/Win32-OpenSSH/releases/latest"
                Write-Host "       下載 OpenSSH-Win64.zip, USB 拷到 SF 主機, 然後跑:"
                Write-Host "       .\scripts\install_openssh_portable.ps1"
                Write-Host "    B. 公司 WSUS 包進 OpenSSH FoD package (找系管確認)"
                Write-Host "    C. 從 Windows installation media 帶 sxs source 過來:"
                Write-Host "       Add-WindowsCapability -Online -Name $($sshCap.Name) -Source <ISO-mount>\sources\sxs"
                Write-Host "    D. GUI 安裝 (短期可用):"
                Write-Host "       設定 → 應用程式 → 選用功能 → 新增功能 → OpenSSH Server"
                Write-Host ""
                Write-Host "  其他套件繼續裝, OpenSSH 之後補上" -ForegroundColor Cyan
                RecordStep 'OpenSSH.Server' 'fail' '0x800f0907 無 FoD source (見上方解法)'
            }
        }
    }
}

# ===== Step 8: Python 套件 =====
if (-not $SkipPython) {
    Step 8 "Python 套件 (pip install --no-index --find-links)"

    # 找 requirements.txt (可能在 bundle 根 / portal/)
    $reqPath = Join-Path $BundleDir 'requirements.txt'
    if (-not (Test-Path $reqPath)) {
        $altReq = Join-Path (Split-Path $BundleDir -Parent) 'portal\requirements.txt'
        if (Test-Path $altReq) { $reqPath = $altReq }
    }

    if ((Test-Path $reqPath) -and (Test-Path $wheelsDir)) {
        # 找 pip (剛裝的 Python 可能還沒進 PATH)
        $pipExe = $null
        $pyCands = @(
            "$env:LOCALAPPDATA\Programs\Python\Python311\Scripts\pip.exe",
            "C:\Program Files\Python311\Scripts\pip.exe"
        )
        foreach ($p in $pyCands) {
            if (Test-Path $p) { $pipExe = $p; break }
        }
        if (-not $pipExe) {
            $pipCmd = Get-Command pip -ErrorAction SilentlyContinue
            if ($pipCmd) { $pipExe = $pipCmd.Source }
        }

        if ($pipExe) {
            $rc = RunCmd -Cmd $pipExe -Args @(
                'install', '--no-index',
                '--find-links', $wheelsDir,
                '-r', $reqPath
            ) -Description "Install Python packages from local wheels"
            if ($rc -eq 0) { RecordStep 'Python 套件' 'ok' '安裝完成' }
            else { RecordStep 'Python 套件' 'warn' "exit=$rc" }
        } else {
            RecordStep 'Python 套件' 'fail' '找不到 pip'
        }
    } else {
        RecordStep 'Python 套件' 'skip' "requirements.txt 或 python_wheels 不存在"
    }
}

# ===== Step 9: 依序跑 deploy/00 ~ 17 =====
if (-not $SkipDeployScripts) {
    Step 9 "執行 deploy/00 ~ 17 設定腳本"

    if (-not (Test-Path $deployDir)) {
        Write-Host "[skip] deploy 目錄不存在: $deployDir" -ForegroundColor Yellow
        RecordStep 'deploy scripts' 'skip' 'deploy/ 不存在'
    } else {
        $scripts = Get-ChildItem $deployDir -Filter '*.ps1' | Sort-Object Name
        $scriptOk = 0; $scriptFail = 0
        foreach ($s in $scripts) {
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
                    $scriptOk++
                } catch {
                    Write-Host "  [warn] $($s.Name) 異常: $($_.Exception.Message)" -ForegroundColor Yellow
                    $scriptFail++
                }
            }
        }
        RecordStep 'deploy scripts' 'ok' "成功 $scriptOk, 失敗 $scriptFail"
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
    RecordStep 'Portal appsettings' 'ok' $appSettings
} else {
    RecordStep 'Portal appsettings' 'skip' '(dry-run 或 D:\_portal\app 未建立)'
}

# ===== Summary =====
$elapsed = (Get-Date) - $startTime
Write-Host ""
Write-Host ("=" * 60) -ForegroundColor Green
Write-Host " 安裝結束 — Summary" -ForegroundColor Green
Write-Host ("=" * 60) -ForegroundColor Green
Write-Host "DB 模式: $DbMode"
Write-Host "耗時:    $($elapsed.ToString('mm\:ss'))"
Write-Host ""

$summary = $script:results | Group-Object status | ForEach-Object {
    "{0}: {1}" -f $_.Name.ToUpper(), $_.Count
}
Write-Host ($summary -join ' | ') -ForegroundColor Cyan
Write-Host ""

# 詳細表格
Write-Host ('-' * 60)
Write-Host ('{0,-25} {1,-6} {2}' -f 'Step', 'Status', 'Detail') -ForegroundColor Cyan
Write-Host ('-' * 60)
foreach ($r in $script:results) {
    $color = switch ($r.status) {
        'ok'   { 'Green' }
        'skip' { 'DarkGray' }
        'warn' { 'Yellow' }
        'fail' { 'Red' }
        default { 'White' }
    }
    Write-Host ('{0,-25} {1,-6} {2}' -f $r.name, $r.status, $r.detail) -ForegroundColor $color
}
Write-Host ('-' * 60)
Write-Host ""

$fails = $script:results | Where-Object { $_.status -eq 'fail' }
if ($fails.Count -gt 0) {
    Write-Host "⚠️  有 $($fails.Count) 個 step 失敗, 請依上方提示處理後重跑此 script (idempotent)" -ForegroundColor Yellow
    Write-Host ""
}

Write-Host "下一步:"
Write-Host "  1. 跑健康檢查:  cd $(Split-Path $BundleDir -Parent)\..; .\scripts\health_check.ps1"
Write-Host "  2. 啟動 SOP:    cat docs\startup_sop.md (8 個 step)"
Write-Host ""

if ($DbMode -eq 'Express') {
    Write-Host "第二階段 (改用公司 DB) 時, 跑:" -ForegroundColor Yellow
    Write-Host "  .\scripts\migrate_db_to_corp.ps1 -CorpDBServer '<server>'" -ForegroundColor Yellow
}
