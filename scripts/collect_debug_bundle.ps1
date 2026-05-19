<#
.SYNOPSIS
    SF 主機 debug bundle 收集器 — 一鍵打包問題排查資料給 GPT Enterprise 分析。
.DESCRIPTION
    自動收集以下資料, 自動去識別化 (sanitize) 後打包成 zip:
    - SF 版本 (version.json)
    - Portal 設定 (移除密碼)
    - 最近 N 天 log (Portal / IIS / OpenSSH / SQL / Scheduled / 防火牆)
    - Windows version / OS info
    - PowerShell version / 安裝套件
    - systemctl/服務狀態
    - 磁碟 / 記憶體狀態
    - 排程工作狀態
    - 近期 AuditLog 摘要 (去識別化)

    輸出: D:\_portal\backups\debug_bundle_YYYYMMDD_HHMMSS.zip
.PARAMETER LogDays
    收集最近幾天的 log, 預設 3。
.PARAMETER OutputDir
    輸出目錄, 預設 D:\_portal\backups。
.PARAMETER NoSanitize
    停用去識別化 (除錯用, 正式環境別用)。
.EXAMPLE
    .\collect_debug_bundle.ps1
.EXAMPLE
    .\collect_debug_bundle.ps1 -LogDays 7
#>
[CmdletBinding()]
param(
    [int]$LogDays = 3,
    [string]$OutputDir = 'D:\_portal\backups',
    [switch]$NoSanitize
)

$ErrorActionPreference = 'Continue'
$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$bundleName = "debug_bundle_$ts"
$workDir = Join-Path $env:TEMP $bundleName

Write-Host "`n=== SF Debug Bundle Collector ===`n" -ForegroundColor Cyan
Write-Host "輸出目錄: $OutputDir"
Write-Host "工作目錄: $workDir"
Write-Host "Log 範圍: 最近 $LogDays 天"
Write-Host "去識別化: $(-not $NoSanitize)`n"

# 建立工作目錄
if (-not (Test-Path $workDir)) { New-Item -Path $workDir -ItemType Directory -Force | Out-Null }
if (-not (Test-Path $OutputDir)) { New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null }

$cutoff = (Get-Date).AddDays(-$LogDays)
$sanitizer = Join-Path $PSScriptRoot 'sanitize_log.ps1'

function Add-ToBundle {
    param(
        [string]$Source,
        [string]$DestSubdir,
        [switch]$DoSanitize
    )
    if (-not (Test-Path $Source)) { return }
    $destDir = Join-Path $workDir $DestSubdir
    if (-not (Test-Path $destDir)) { New-Item -Path $destDir -ItemType Directory -Force | Out-Null }
    $destFile = Join-Path $destDir (Split-Path $Source -Leaf)

    if ($DoSanitize -and -not $NoSanitize -and (Test-Path $sanitizer)) {
        & $sanitizer -InputPath $Source -OutputPath $destFile
    } else {
        Copy-Item $Source $destFile -Force
    }
}

# ===== 1. 系統資訊 =====
Write-Host "[1/9] 收集系統資訊..." -ForegroundColor Yellow
$sysInfo = @{
    Hostname = $env:COMPUTERNAME
    CollectedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    OS = (Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, OSArchitecture, LastBootUpTime)
    PowerShell = $PSVersionTable
    Uptime = ((Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime).ToString()
    Domain = (Get-CimInstance Win32_ComputerSystem).Domain
    Timezone = (Get-TimeZone).DisplayName
}
$sysInfo | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $workDir 'system_info.json')

# ===== 2. SF 版本資訊 =====
Write-Host "[2/9] SF 版本..." -ForegroundColor Yellow
$versionFile = 'D:\_portal\app\version.json'
if (Test-Path $versionFile) {
    Copy-Item $versionFile (Join-Path $workDir 'sf_version.json') -Force
} else {
    @{ note = 'version.json 不存在'; path = $versionFile } | ConvertTo-Json | Set-Content (Join-Path $workDir 'sf_version.json')
}

# ===== 3. 服務狀態 =====
Write-Host "[3/9] 服務狀態..." -ForegroundColor Yellow
$services = @('sshd', 'W3SVC', 'MSSQL$SQLEXPRESS', 'LanmanServer', 'W32Time', 'FTPSVC', 'WinDefend', 'MpsSvc')
$svcStatus = foreach ($s in $services) {
    $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
    if ($svc) {
        [PSCustomObject]@{ Name = $svc.Name; Status = $svc.Status.ToString(); StartType = $svc.StartType.ToString() }
    } else {
        [PSCustomObject]@{ Name = $s; Status = 'NOT_FOUND'; StartType = '-' }
    }
}
$svcStatus | ConvertTo-Json | Set-Content (Join-Path $workDir 'services.json')

# ===== 4. 磁碟 / 記憶體 =====
Write-Host "[4/9] 磁碟 + 記憶體..." -ForegroundColor Yellow
$resources = @{
    Disks = Get-PSDrive -PSProvider FileSystem | Select-Object Name, Used, Free, @{n='UsedPct'; e={ if (($_.Used + $_.Free) -gt 0) { [math]::Round($_.Used * 100 / ($_.Used + $_.Free), 1) } else { 0 } }}
    Memory = Get-CimInstance Win32_OperatingSystem | Select-Object TotalVisibleMemorySize, FreePhysicalMemory, @{n='UsedPct'; e={ [math]::Round((1 - $_.FreePhysicalMemory / $_.TotalVisibleMemorySize) * 100, 1) }}
    CPU = (Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 2 -MaxSamples 3).CounterSamples | Measure-Object -Property CookedValue -Average | Select-Object -ExpandProperty Average
}
$resources | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $workDir 'resources.json')

# ===== 5. 排程工作狀態 =====
Write-Host "[5/9] 排程工作..." -ForegroundColor Yellow
$tasks = Get-ScheduledTask -TaskPath '\' -ErrorAction SilentlyContinue |
    Where-Object { $_.TaskName -like 'SF_*' } |
    ForEach-Object {
        $info = $_ | Get-ScheduledTaskInfo
        [PSCustomObject]@{
            TaskName = $_.TaskName
            State = $_.State.ToString()
            LastRun = $info.LastRunTime
            LastResult = $info.LastTaskResult
            NextRun = $info.NextRunTime
        }
    }
$tasks | ConvertTo-Json | Set-Content (Join-Path $workDir 'scheduled_tasks.json')

# ===== 6. 防火牆規則 =====
Write-Host "[6/9] 防火牆規則..." -ForegroundColor Yellow
Get-NetFirewallRule -Direction Inbound -Enabled True -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -like '*FileExchange*' -or $_.DisplayName -like '*OpenSSH*' -or $_.DisplayName -like 'FX-*' } |
    Select-Object Name, DisplayName, Direction, Action, Profile |
    ConvertTo-Json | Set-Content (Join-Path $workDir 'firewall_rules.json')

# ===== 7. Log 檔 (去識別化) =====
Write-Host "[7/9] 收集 log (最近 $LogDays 天)..." -ForegroundColor Yellow

# Portal app log
Get-ChildItem 'D:\_portal\logs\*.log' -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -gt $cutoff } |
    ForEach-Object { Add-ToBundle -Source $_.FullName -DestSubdir 'logs\portal' -DoSanitize }

# 排程工作 log
Get-ChildItem 'D:\_portal\logs\scheduled\*.log' -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -gt $cutoff } |
    ForEach-Object { Add-ToBundle -Source $_.FullName -DestSubdir 'logs\scheduled' -DoSanitize }

# IIS access log
Get-ChildItem 'C:\inetpub\logs\LogFiles\W3SVC*\*.log' -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -gt $cutoff } |
    Select-Object -Last 3 |
    ForEach-Object { Add-ToBundle -Source $_.FullName -DestSubdir 'logs\iis' -DoSanitize }

# OpenSSH log
Get-ChildItem 'C:\ProgramData\ssh\logs\sshd.log*' -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -gt $cutoff } |
    ForEach-Object { Add-ToBundle -Source $_.FullName -DestSubdir 'logs\openssh' -DoSanitize }

# 防火牆 log
$fwLog = 'C:\Windows\System32\LogFiles\Firewall\pfirewall.log'
if (Test-Path $fwLog) {
    Add-ToBundle -Source $fwLog -DestSubdir 'logs\firewall' -DoSanitize
}

# ===== 8. Event Log 摘要 =====
Write-Host "[8/9] Event Log 摘要..." -ForegroundColor Yellow
$evtSummary = @{}
foreach ($logName in @('Application', 'System', 'Security', 'OpenSSH/Operational')) {
    try {
        $events = Get-WinEvent -FilterHashtable @{LogName=$logName; StartTime=$cutoff; Level=1,2,3} -MaxEvents 100 -ErrorAction SilentlyContinue
        $evtSummary[$logName] = $events | Group-Object Id, LevelDisplayName | Sort-Object Count -Descending | Select-Object -First 20 |
            ForEach-Object { @{ Id = ($_.Name -split ', ')[0]; Level = ($_.Name -split ', ')[1]; Count = $_.Count } }
    } catch {
        $evtSummary[$logName] = "Error: $_"
    }
}
$evtSummary | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $workDir 'event_log_summary.json')

# ===== 9. 設定檔 (去識別化) =====
Write-Host "[9/9] 設定檔 (去識別化)..." -ForegroundColor Yellow
$configs = @(
    'C:\ProgramData\ssh\sshd_config',
    'C:\inetpub\wwwroot\Portal\web.config',
    'D:\_portal\app\appsettings.json'
)
foreach ($c in $configs) {
    if (Test-Path $c) {
        Add-ToBundle -Source $c -DestSubdir 'config' -DoSanitize
    }
}

# ===== 打包 =====
Write-Host "`n打包中..." -ForegroundColor Yellow
$zipPath = Join-Path $OutputDir "$bundleName.zip"
Compress-Archive -Path "$workDir\*" -DestinationPath $zipPath -Force
Remove-Item $workDir -Recurse -Force -ErrorAction SilentlyContinue

$zipInfo = Get-Item $zipPath
$sizeKB = [math]::Round($zipInfo.Length / 1KB, 1)

Write-Host "`n=== 完成 ===" -ForegroundColor Green
Write-Host "輸出: $zipPath ($sizeKB KB)"
Write-Host "`n下一步: 把 zip 上傳到 GPT Enterprise (內部版), 提示語建議:"
Write-Host "  以下是公司 SF 主機的去識別化 debug bundle, 請協助判斷:" -ForegroundColor Cyan
Write-Host "  1. root cause 是什麼?" -ForegroundColor Cyan
Write-Host "  2. 可能修法為何?" -ForegroundColor Cyan
Write-Host "  3. 需要再補哪些 log?" -ForegroundColor Cyan
Write-Host "  4. 下一步排查順序" -ForegroundColor Cyan
Write-Host ""
Write-Host "⚠️ 注意: 內部 log 與主機資訊**只用 GPT Enterprise**, 不要丟個人 GPT Pro / Free" -ForegroundColor Yellow
