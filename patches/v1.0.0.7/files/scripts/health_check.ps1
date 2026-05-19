<#
.SYNOPSIS
    SF 主機健康速查 — 不上 Portal 也能在 PowerShell 看狀態。
.DESCRIPTION
    一鍵檢查 SF 主機所有核心狀態:
    - 服務狀態 (sshd / IIS / SQL / SMB / W32Time / FTPS / Defender)
    - 磁碟 / 記憶體 / CPU
    - 排程工作上次執行結果
    - 防火牆規則 (FX-* 系列)
    - 近期 SFTP 認證失敗統計
    - NTP 同步狀態
    - AuditLog DB 連線測試
    - 最近 24 小時 ERROR / WARN 事件數

    可在 RDP 上 SF 後快速跑這個取代多個 GUI 工具。
.PARAMETER Json
    輸出 JSON 格式 (給 Portal 或其他系統 parse), 預設文字。
.EXAMPLE
    .\health_check.ps1
.EXAMPLE
    .\health_check.ps1 -Json
#>
[CmdletBinding()]
param(
    [switch]$Json
)

$ErrorActionPreference = 'Continue'
$results = [ordered]@{}

# 顯示函式
function Show {
    param([string]$Name, [bool]$OK, [string]$Detail = '')
    if (-not $Json) {
        $mark = if ($OK) { '[ OK ]' } else { '[FAIL]' }
        $color = if ($OK) { 'Green' } else { 'Red' }
        Write-Host ("{0}  {1}  {2}" -f $mark, $Name.PadRight(35), $Detail) -ForegroundColor $color
    }
    $results[$Name] = @{ ok = $OK; detail = $Detail }
}

function ShowInfo {
    param([string]$Name, [string]$Detail)
    if (-not $Json) {
        Write-Host ("[INFO]  {0}  {1}" -f $Name.PadRight(35), $Detail) -ForegroundColor Cyan
    }
    $results[$Name] = @{ ok = $true; detail = $Detail; type = 'info' }
}

if (-not $Json) {
    Write-Host "`n=== SF 主機健康速查 ===" -ForegroundColor Cyan
    Write-Host ("時間: {0}  主機: {1}`n" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $env:COMPUTERNAME)
}

# ===== 1. 核心服務 =====
$services = @{
    'sshd' = 'OpenSSH SFTP'
    'W3SVC' = 'IIS Web Server'
    'MSSQL$SQLEXPRESS' = 'SQL Server Express'
    'LanmanServer' = 'SMB Server'
    'W32Time' = 'NTP 時間同步'
    'WinDefend' = 'Defender'
    'MpsSvc' = 'Windows Firewall'
}
foreach ($svcName in $services.Keys) {
    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    $ok = $svc -and $svc.Status -eq 'Running'
    $detail = if ($svc) { "$($services[$svcName]): $($svc.Status)" } else { "$($services[$svcName]): NOT FOUND" }
    Show -Name "Service: $svcName" -OK $ok -Detail $detail
}

# FTPS (預設停用, 不算 FAIL)
$ftps = Get-Service -Name 'FTPSVC' -ErrorAction SilentlyContinue
if ($ftps) {
    ShowInfo -Name 'Service: FTPSVC' -Detail "FTPS 備案: $($ftps.Status) / $($ftps.StartType) (預設 Manual)"
}

# ===== 2. 磁碟 =====
$dDrive = Get-PSDrive D -ErrorAction SilentlyContinue
if ($dDrive) {
    $usedPct = [math]::Round($dDrive.Used * 100 / ($dDrive.Used + $dDrive.Free), 1)
    $freeGB = [math]::Round($dDrive.Free / 1GB, 1)
    $ok = $usedPct -lt 80
    Show -Name 'D: 磁碟使用率' -OK $ok -Detail "$usedPct% 已用, 剩 $freeGB GB"
}

# ===== 3. 記憶體 =====
$mem = Get-CimInstance Win32_OperatingSystem
$memUsedPct = [math]::Round((1 - $mem.FreePhysicalMemory / $mem.TotalVisibleMemorySize) * 100, 1)
$totalGB = [math]::Round($mem.TotalVisibleMemorySize / 1MB, 1)
Show -Name '記憶體使用率' -OK ($memUsedPct -lt 90) -Detail "$memUsedPct% / $totalGB GB"

# ===== 4. CPU (3 秒取樣) =====
$cpu = (Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples 3 -ErrorAction SilentlyContinue).CounterSamples |
       Measure-Object -Property CookedValue -Average | Select-Object -ExpandProperty Average
$cpuRounded = [math]::Round($cpu, 1)
Show -Name 'CPU 使用率' -OK ($cpuRounded -lt 80) -Detail "$cpuRounded%"

# ===== 5. NTP 同步狀態 =====
$ntpStatus = (& w32tm /query /status 2>&1) -join "`n"
$ntpOK = $ntpStatus -match 'Last Successful Sync Time' -and $ntpStatus -notmatch 'has not synchronized'
# PS 5.1 compat: Select-String 找不到時回 null, 直接 .ToString() 會炸
$ntpMatch = $ntpStatus | Select-String -Pattern 'Source:.*$' | Select-Object -First 1
$ntpSrc = if ($ntpMatch) { $ntpMatch.ToString().Trim() } else { '(無 Source 資訊)' }
Show -Name 'NTP 同步' -OK $ntpOK -Detail $ntpSrc

# ===== 6. 排程工作 =====
$sfTasks = Get-ScheduledTask -TaskPath '\' -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like 'SF_*' }
foreach ($t in $sfTasks) {
    $info = $t | Get-ScheduledTaskInfo
    $ok = $info.LastTaskResult -eq 0
    $detail = "上次: $($info.LastRunTime) (result=$($info.LastTaskResult))"
    Show -Name "Task: $($t.TaskName)" -OK $ok -Detail $detail
}

# ===== 7. AuditLog DB 連線 =====
try {
    $conn = New-Object System.Data.SqlClient.SqlConnection('Server=.\SQLEXPRESS;Database=FileExchangeAudit;Integrated Security=True;Connection Timeout=3')
    $conn.Open()
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = "SELECT COUNT(*) FROM AuditLog WHERE event_time > DATEADD(hour, -24, GETDATE())"
    $count = $cmd.ExecuteScalar()
    $conn.Close()
    Show -Name 'AuditLog DB' -OK $true -Detail "連線 OK, 近 24 小時 $count 筆"
} catch {
    Show -Name 'AuditLog DB' -OK $false -Detail "連線失敗: $($_.Exception.Message.Split("`n")[0])"
}

# ===== 8. 近 24 小時 SFTP 認證失敗 =====
try {
    $start = (Get-Date).AddHours(-24)
    $sshFails = (Get-WinEvent -FilterHashtable @{LogName='OpenSSH/Operational'; Level=2; StartTime=$start} -ErrorAction SilentlyContinue | Measure-Object).Count
    Show -Name 'SFTP 認證失敗 (24h)' -OK ($sshFails -lt 20) -Detail "$sshFails 次 (>20 可能暴力破解)"
} catch {
    ShowInfo -Name 'SFTP 認證失敗' -Detail "查詢失敗 (OpenSSH log 可能未啟用)"
}

# ===== 9. Event Log Error/Warn 統計 =====
$start = (Get-Date).AddHours(-24)
foreach ($logName in @('Application', 'System')) {
    try {
        $errCount = (Get-WinEvent -FilterHashtable @{LogName=$logName; Level=1,2; StartTime=$start} -ErrorAction SilentlyContinue | Measure-Object).Count
        ShowInfo -Name "Event Log: $logName" -Detail "$errCount 筆 Error/Critical (24h)"
    } catch {}
}

# ===== 10. 防火牆規則 (FX-* 系列) =====
$fwCount = (Get-NetFirewallRule -Direction Inbound -Enabled True -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'FX-*' -or $_.DisplayName -like '*FileExchange*' } | Measure-Object).Count
Show -Name '防火牆 FX 規則' -OK ($fwCount -ge 3) -Detail "$fwCount 條啟用中"

# ===== 11. 上次 Defender 病毒碼更新 =====
$defStatus = Get-MpComputerStatus -ErrorAction SilentlyContinue
if ($defStatus) {
    try {
        # AntivirusSignatureLastUpdated 在某些 PS 5.1 環境可能是 string, 強制 cast
        $sigDate = [datetime]$defStatus.AntivirusSignatureLastUpdated
        $sigAge = ((Get-Date) - $sigDate).TotalHours
        Show -Name 'Defender 病毒碼' -OK ($sigAge -lt 48) -Detail "上次更新 $([math]::Round($sigAge,1)) 小時前"
    } catch {
        ShowInfo -Name 'Defender 病毒碼' -Detail "查詢失敗 ($($_.Exception.Message.Split("`n")[0]))"
    }
}

# ===== 輸出 =====
if ($Json) {
    $output = @{
        timestamp = (Get-Date).ToString('o')
        hostname = $env:COMPUTERNAME
        checks = $results
        overall_ok = -not ($results.Values | Where-Object { $_.ok -eq $false } | Select-Object -First 1)
    }
    $output | ConvertTo-Json -Depth 5
} else {
    Write-Host ""
    $failCount = ($results.Values | Where-Object { $_.ok -eq $false } | Measure-Object).Count
    if ($failCount -eq 0) {
        Write-Host "===== 全部 OK ✓ =====" -ForegroundColor Green
    } else {
        Write-Host "===== 有 $failCount 項異常, 請檢查上方 [FAIL] =====" -ForegroundColor Red
    }
}
