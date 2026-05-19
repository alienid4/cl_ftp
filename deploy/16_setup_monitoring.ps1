<#
.SYNOPSIS
    設定主機效能監控與告警 (對齊主管圖「監控與告警」要求)。
.DESCRIPTION
    - 建立 PerfMon Data Collector Set 收集 CPU / Memory / Disk / Network
    - 排程每 5 分鐘檢查告警閾值, 超過寄 mail
    - 不依賴外部監控平台 (該由 SIEM 階段二接管)
.PARAMETER MailTo
    告警收件人, 預設 'it-admin@corp.local'。
.PARAMETER SmtpServer
    SMTP relay 主機, 預設 'mail-relay.corp.local'。
.PARAMETER DryRun
    只列出將執行的動作, 不實際套用。
#>
[CmdletBinding()]
param(
    [string]$MailTo = 'it-admin@corp.local',
    [string]$SmtpServer = 'mail-relay.corp.local',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

Write-Host "`n=== 設定主機效能監控 + 告警 ===`n" -ForegroundColor Cyan

$scriptDir = 'D:\_portal\scripts'
$monitorScript = Join-Path $scriptDir 'monitoring_check.ps1'

if (-not (Test-Path $scriptDir)) {
    if (-not $DryRun) {
        New-Item -Path $scriptDir -ItemType Directory -Force | Out-Null
    }
}

# 1. 產生監控腳本
$monitorCode = @"
# SF 主機監控檢查 (由 16_setup_monitoring.ps1 產生)
`$ErrorActionPreference = 'Continue'
`$logFile = 'D:\_portal\logs\monitoring_' + (Get-Date -Format 'yyyyMMdd') + '.log'
`$mailTo = '$MailTo'
`$smtp = '$SmtpServer'
`$alerts = @()

# CPU 使用率
`$cpu = (Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 2 -MaxSamples 5).CounterSamples |
       Measure-Object -Property CookedValue -Average | Select-Object -ExpandProperty Average
if (`$cpu -gt 80) { `$alerts += "CPU 使用率 `$([math]::Round(`$cpu,1))% (>80%)" }

# Memory 使用率
`$mem = Get-CimInstance Win32_OperatingSystem
`$memUsedPct = 100 - (`$mem.FreePhysicalMemory * 100 / `$mem.TotalVisibleMemorySize)
if (`$memUsedPct -gt 90) { `$alerts += "Memory `$([math]::Round(`$memUsedPct,1))% (>90%)" }

# D: 磁碟使用率
`$disk = Get-PSDrive D
`$diskUsedPct = (`$disk.Used / (`$disk.Used + `$disk.Free)) * 100
if (`$diskUsedPct -gt 80) { `$alerts += "D: 磁碟 `$([math]::Round(`$diskUsedPct,1))% (>80%)" }
if (`$diskUsedPct -gt 95) { `$alerts += "[嚴重] D: 磁碟 `$([math]::Round(`$diskUsedPct,1))% (>95%)" }

# 核心服務狀態
`$services = @('sshd', 'W3SVC', 'MSSQL`$SQLEXPRESS', 'LanmanServer', 'W32Time')
foreach (`$svc in `$services) {
    `$s = Get-Service -Name `$svc -ErrorAction SilentlyContinue
    if (`$s -and `$s.Status -ne 'Running') {
        `$alerts += "服務 `$svc 異常 (狀態: `$(`$s.Status))"
    }
}

# 暴力破解偵測 (近 1 小時 SFTP 認證失敗 > 10)
try {
    `$startTime = (Get-Date).AddHours(-1)
    `$failCount = (Get-WinEvent -FilterHashtable @{LogName='OpenSSH/Operational';Level=2;StartTime=`$startTime} -ErrorAction SilentlyContinue | Measure-Object).Count
    if (`$failCount -gt 10) { `$alerts += "SFTP 認證失敗 `$failCount 次 (>10/小時, 可能暴力破解)" }
} catch {}

# 記錄結果
`$ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
if (`$alerts.Count -gt 0) {
    Add-Content -Path `$logFile -Value "[`$ts] ALERT: `$(`$alerts -join '; ')"

    # 寄 mail
    `$body = "SF 主機監控告警:`n`n" + (`$alerts -join "`n") + "`n`n時間: `$ts`n主機: `$env:COMPUTERNAME"
    try {
        Send-MailMessage -To `$mailTo -From "sf-monitor@corp.local" -Subject "[SF] 主機告警" `
            -Body `$body -SmtpServer `$smtp -ErrorAction Stop
    } catch {
        Add-Content -Path `$logFile -Value "[`$ts] Mail 寄送失敗: `$_"
    }
} else {
    Add-Content -Path `$logFile -Value "[`$ts] OK (CPU `$([math]::Round(`$cpu,1))% / Mem `$([math]::Round(`$memUsedPct,1))% / D `$([math]::Round(`$diskUsedPct,1))%)"
}
"@

if ($DryRun) {
    Write-Host "[dry ] Write monitoring script to $monitorScript"
} else {
    Set-Content -Path $monitorScript -Value $monitorCode -Encoding UTF8
    Write-Host "[ok  ] 監控腳本已產生: $monitorScript"
}

# 2. 建立排程工作 (每 5 分鐘)
$taskName = 'SF_Monitoring_Check'

if ($DryRun) {
    Write-Host "[dry ] Register-ScheduledTask $taskName 每 5 分鐘"
} else {
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$monitorScript`""

    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
        -RepetitionInterval (New-TimeSpan -Minutes 5)

    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopIfGoingOnBatteries

    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
        -Principal $principal -Settings $settings `
        -Description "SF 主機 5 分鐘監控檢查 (CPU/Mem/Disk/Service/SFTP brute force)" | Out-Null

    Write-Host "[ok  ] 排程工作 $taskName 已建立 (每 5 分鐘)"
}

# 3. 建立 PerfMon Data Collector Set (長期收集, 看趨勢)
if ($DryRun) {
    Write-Host "[dry ] Create PerfMon Data Collector Set 'SF_Performance'"
} else {
    $collectorXml = @"
<?xml version="1.0" encoding="UTF-8"?>
<DataCollectorSet>
  <Name>SF_Performance</Name>
  <OutputLocation>D:\_portal\logs\perfmon</OutputLocation>
  <Duration>0</Duration>
  <SchedulesEnabled>1</SchedulesEnabled>
  <PerformanceCounterDataCollector>
    <Name>SF_Perf</Name>
    <SampleInterval>30</SampleInterval>
    <Counter>\Processor(_Total)\% Processor Time</Counter>
    <Counter>\Memory\Available MBytes</Counter>
    <Counter>\LogicalDisk(D:)\% Free Space</Counter>
    <Counter>\Network Interface(*)\Bytes Total/sec</Counter>
    <Counter>\System\Processor Queue Length</Counter>
  </PerformanceCounterDataCollector>
</DataCollectorSet>
"@
    $xmlPath = Join-Path $scriptDir 'perfmon_collector.xml'
    Set-Content -Path $xmlPath -Value $collectorXml -Encoding UTF8

    # 建立 collector
    & logman create counter SF_Performance -xml $xmlPath 2>&1 | Out-Null
    & logman start SF_Performance 2>&1 | Out-Null

    Write-Host "[ok  ] PerfMon Collector Set 'SF_Performance' 建立"
}

Write-Host "`n監控設定完成。告警 mail 送 $MailTo via $SmtpServer" -ForegroundColor Green
Write-Host "PerfMon log: D:\_portal\logs\perfmon\" -ForegroundColor Yellow
Write-Host "查詢: Get-ScheduledTask -TaskName $taskName | Get-ScheduledTaskInfo" -ForegroundColor Yellow
