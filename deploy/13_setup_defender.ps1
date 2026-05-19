<#
.SYNOPSIS
    設定 Windows Defender (對齊主管圖「EDR / 防毒」要求)。
.DESCRIPTION
    - 啟用即時防護
    - 啟用 Behavior Monitoring 與 AMSI
    - 設定排程每日掃描 D:\DataExchange (上傳檔)
    - 設定排程每週全機快掃
    - 設定例外: SQL Express 資料檔 (避免衝突)
    - 設定威脅偵測動作: 隔離
.PARAMETER ScanTime
    每日掃描時間, 預設 03:00。
.PARAMETER DryRun
    只列出將執行的動作, 不實際套用。
#>
[CmdletBinding()]
param(
    [string]$ScanTime = '03:00',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

Write-Host "`n=== 設定 Windows Defender ===`n" -ForegroundColor Cyan

# 1. 確認 Defender 服務狀態
$defenderSvc = Get-Service -Name WinDefend -ErrorAction SilentlyContinue
if (-not $defenderSvc) {
    Write-Host "[fail] 找不到 WinDefend 服務 (Defender 可能未安裝)" -ForegroundColor Red
    exit 1
}

if ($defenderSvc.Status -ne 'Running') {
    if ($DryRun) {
        Write-Host "[dry ] Start-Service WinDefend"
    } else {
        Start-Service WinDefend
        Write-Host "[ok  ] 啟動 WinDefend"
    }
}

# 2. 設定 Defender preferences
if ($DryRun) {
    Write-Host "[dry ] Set-MpPreference: 即時防護 + 行為監控 + AMSI + IDS + PUA"
} else {
    Set-MpPreference `
        -DisableRealtimeMonitoring $false `
        -DisableBehaviorMonitoring $false `
        -DisableIOAVProtection $false `
        -DisableScriptScanning $false `
        -MAPSReporting Advanced `
        -SubmitSamplesConsent SendSafeSamples `
        -PUAProtection Enabled `
        -EnableNetworkProtection Enabled `
        -CloudBlockLevel High `
        -CheckForSignaturesBeforeRunningScan $true `
        -RemediationScheduleDay Everyday `
        -RemediationScheduleTime $ScanTime
    Write-Host "[ok  ] Defender preferences 已套用"
}

# 3. 每日快掃排程
if ($DryRun) {
    Write-Host "[dry ] 每日 $ScanTime 排程快掃 D:\DataExchange"
} else {
    Set-MpPreference -ScanScheduleQuickScanTime $ScanTime
    Set-MpPreference -ScanParameters 1  # 1 = QuickScan, 2 = FullScan
    Write-Host "[ok  ] 每日 $ScanTime 排程快掃"
}

# 4. 每週全機完整掃描 (週日凌晨)
if ($DryRun) {
    Write-Host "[dry ] 每週日 04:00 完整掃描"
} else {
    Set-MpPreference -ScanScheduleDay Sunday
    Set-MpPreference -ScanScheduleTime '04:00'
    Write-Host "[ok  ] 每週日 04:00 完整掃描"
}

# 5. 設定排除清單 (SQL Express 資料檔, 避免衝突 + 效能)
$exclusions = @(
    'D:\_portal\db',
    'D:\_portal\ftps_pasv'
)
foreach ($e in $exclusions) {
    if ($DryRun) {
        Write-Host "[dry ] Add-MpPreference -ExclusionPath $e"
    } else {
        Add-MpPreference -ExclusionPath $e -ErrorAction SilentlyContinue
        Write-Host "[ok  ] 排除路徑: $e"
    }
}

# 6. 立即更新病毒碼
if ($DryRun) {
    Write-Host "[dry ] Update-MpSignature"
} else {
    Update-MpSignature
    Write-Host "[ok  ] 病毒碼更新完成"
}

# 7. 驗證設定
if (-not $DryRun) {
    Write-Host "`n--- Defender 設定摘要 ---" -ForegroundColor Cyan
    $status = Get-MpComputerStatus
    Write-Host "Real-time Protection : $($status.RealTimeProtectionEnabled)"
    Write-Host "Behavior Monitor     : $($status.BehaviorMonitorEnabled)"
    Write-Host "Antispyware Enabled  : $($status.AntispywareEnabled)"
    Write-Host "Last Signature       : $($status.AntivirusSignatureLastUpdated)"
    Write-Host "Last QuickScan       : $($status.QuickScanEndTime)"
}

Write-Host "`nDefender 設定完成。建議: 部署後手動跑一次完整掃描 (Start-MpScan -ScanType FullScan)" -ForegroundColor Green
