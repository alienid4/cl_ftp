<#
.SYNOPSIS
    SF 主機即時 log 監看 — 不打包不分析, 直接 tail 看, 秒級可用。
.DESCRIPTION
    比 collect_debug_bundle.ps1 快 100 倍。場景:
    - 故障當下, 不想等 3 分鐘打包, 要立刻看「現在在發生什麼」
    - 觀察某個操作的即時 log (例如重啟服務、有人在簽核)

    四種模式:
    1. 預設           - 抓全部主要 log 最後 50 行 (秒級), 不持續更新
    2. -Follow        - 持續追蹤新行 (像 tail -f), Ctrl+C 結束
    3. -ErrorsOnly    - 只看 ERROR / WARN / FAIL 那些行
    4. -Source <name> - 只看特定 log (portal / iis / openssh / sql / firewall / scheduled)
.PARAMETER Source
    指定單一 log 來源, 不指定就抓全部。可選: portal / iis / openssh / sql / firewall / scheduled
.PARAMETER Lines
    每個 log 顯示最後幾行, 預設 50。
.PARAMETER Follow
    持續追蹤新行 (Get-Content -Wait), Ctrl+C 結束。
.PARAMETER ErrorsOnly
    只顯示包含 error / warn / fail / exception / denied 的行。
.PARAMETER Since
    只顯示最近 N 分鐘的內容, 預設 30 分鐘。
.EXAMPLE
    # 立刻看全部 log 最新狀況 (秒級)
    .\tail_log.ps1
.EXAMPLE
    # 持續追 Portal log
    .\tail_log.ps1 -Source portal -Follow
.EXAMPLE
    # 看最近 5 分鐘所有錯誤
    .\tail_log.ps1 -ErrorsOnly -Since 5
.EXAMPLE
    # 只看 SFTP 認證問題, 持續追
    .\tail_log.ps1 -Source openssh -Follow -ErrorsOnly
#>
[CmdletBinding()]
param(
    [ValidateSet('portal', 'iis', 'openssh', 'sql', 'firewall', 'scheduled', 'all')]
    [string]$Source = 'all',
    [int]$Lines = 50,
    [switch]$Follow,
    [switch]$ErrorsOnly,
    [int]$Since = 30
)

$ErrorActionPreference = 'SilentlyContinue'

# Log 來源對照
$logSources = @{
    'portal'    = @{ Path = 'D:\_portal\logs\app.log';                     Color = 'Cyan';    Label = '[PORTAL]' }
    'iis'       = @{ Path = "C:\inetpub\logs\LogFiles\W3SVC1\u_ex$(Get-Date -Format yyMMdd).log"; Color = 'Magenta'; Label = '[IIS]   ' }
    'openssh'   = @{ Path = 'C:\ProgramData\ssh\logs\sshd.log';            Color = 'Green';   Label = '[SSHD]  ' }
    'sql'       = @{ Path = 'C:\Program Files\Microsoft SQL Server\MSSQL16.SQLEXPRESS\MSSQL\Log\ERRORLOG'; Color = 'DarkYellow'; Label = '[SQL]   ' }
    'firewall'  = @{ Path = 'C:\Windows\System32\LogFiles\Firewall\pfirewall.log'; Color = 'DarkGray'; Label = '[FW]    ' }
    'scheduled' = @{ Path = 'D:\_portal\logs\scheduled';                   Color = 'Yellow';  Label = '[SCHED] ' }  # 是目錄
}

# 過濾關鍵字 (ErrorsOnly 模式)
$errorPattern = '(?i)\b(error|errno|fail|fatal|critical|warn|warning|exception|traceback|denied|refused|timeout|unauthor)\b'

function Get-RecentLogContent {
    param(
        [string]$Path,
        [int]$LinesToRead,
        [int]$MinutesAgo,
        [switch]$FilterErrors
    )

    if (-not (Test-Path $Path)) {
        return @("(檔案不存在: $Path)")
    }

    # 取最後 N*5 行 (預留過濾扣減)
    $rawLines = Get-Content $Path -Tail ($LinesToRead * 5) -ErrorAction SilentlyContinue
    if (-not $rawLines) { return @() }

    # 過濾錯誤 (如果啟用)
    if ($FilterErrors) {
        $rawLines = $rawLines | Where-Object { $_ -match $errorPattern }
    }

    # 時間過濾 (盡力解析常見時間格式)
    if ($MinutesAgo -gt 0) {
        $cutoff = (Get-Date).AddMinutes(-$MinutesAgo)
        $rawLines = $rawLines | Where-Object {
            # 嘗試從行首擷取時間
            if ($_ -match '^(\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2})') {
                try {
                    return ([datetime]::Parse($matches[1])) -gt $cutoff
                } catch { return $true }
            }
            return $true   # 解析不到就顯示
        }
    }

    return ($rawLines | Select-Object -Last $LinesToRead)
}

function Show-LogLine {
    param([string]$Label, [string]$Line, [string]$Color)
    # 高亮 error / warn
    if ($Line -match '(?i)\b(error|fatal|critical|denied|refused)\b') {
        Write-Host "$Label $Line" -ForegroundColor Red
    } elseif ($Line -match '(?i)\b(warn|warning|timeout|fail)\b') {
        Write-Host "$Label $Line" -ForegroundColor Yellow
    } else {
        Write-Host "$Label $Line" -ForegroundColor $Color
    }
}

# 決定要看哪些 source
$selectedSources = if ($Source -eq 'all') {
    @('portal', 'openssh', 'iis', 'sql', 'firewall')   # 不含 scheduled (目錄)
} else {
    @($Source)
}

Write-Host "`n=== SF Log Tail ===" -ForegroundColor Cyan
Write-Host "Mode: $($Follow ? 'Follow' : 'Snapshot'), Errors only: $ErrorsOnly, Since: $Since min, Lines: $Lines"
Write-Host "Sources: $($selectedSources -join ', ')`n"

# ===== 模式 1+3+4: 快照 (不 Follow) =====
if (-not $Follow) {
    foreach ($src in $selectedSources) {
        $info = $logSources[$src]
        Write-Host ""
        Write-Host "=== $($info.Label.Trim()) $($info.Path) ===" -ForegroundColor $info.Color
        $lines = Get-RecentLogContent -Path $info.Path -LinesToRead $Lines -MinutesAgo $Since -FilterErrors:$ErrorsOnly

        if ($lines.Count -eq 0) {
            Write-Host "  (無符合條件的行)" -ForegroundColor DarkGray
        } else {
            foreach ($line in $lines) {
                Show-LogLine -Label $info.Label -Line $line -Color $info.Color
            }
        }
    }

    Write-Host "`n--- 完成 (秒級快照) ---" -ForegroundColor Green
    Write-Host "持續追蹤請加 -Follow, 只看錯誤請加 -ErrorsOnly" -ForegroundColor DarkGray
    return
}

# ===== 模式 2: Follow (持續追蹤) =====
Write-Host "持續追蹤 ($($selectedSources.Count) 個來源), Ctrl+C 結束..." -ForegroundColor Yellow
Write-Host ""

# 用 Background Jobs 同時 tail 多個檔
$jobs = @()
foreach ($src in $selectedSources) {
    $info = $logSources[$src]
    if (-not (Test-Path $info.Path)) {
        Write-Host "[skip] $src : 檔案不存在 $($info.Path)" -ForegroundColor DarkGray
        continue
    }
    $jobs += Start-Job -ArgumentList $info.Path, $info.Label, $info.Color, $ErrorsOnly, $errorPattern -ScriptBlock {
        param($path, $label, $color, $errorsOnly, $pattern)
        Get-Content -Path $path -Wait -Tail 0 | ForEach-Object {
            if ($errorsOnly -and ($_ -notmatch $pattern)) { return }
            "$label$_"
        }
    }
}

# 輪詢輸出
try {
    while ($true) {
        foreach ($job in $jobs) {
            $output = Receive-Job -Job $job
            foreach ($line in $output) {
                # 找出 label 對應顏色
                $color = 'White'
                foreach ($s in $logSources.Values) {
                    if ($line.StartsWith($s.Label)) {
                        $color = $s.Color
                        break
                    }
                }
                Show-LogLine -Label '' -Line $line -Color $color
            }
        }
        Start-Sleep -Milliseconds 500
    }
} finally {
    Write-Host "`n停止追蹤, 清理 jobs..." -ForegroundColor Yellow
    $jobs | Stop-Job
    $jobs | Remove-Job -Force
}
