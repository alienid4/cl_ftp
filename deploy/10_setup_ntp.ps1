<#
.SYNOPSIS
    設定 SF 主機 NTP 時間同步 (對齊主管圖「NTP 時間同步」要求)。
.DESCRIPTION
    確保 SF 主機時間與公司 NTP server 同步, 讓 AuditLog 時間能與 PAM/AP/SIEM 對得起來。
    沒有 NTP 同步, 跨系統事件鏈追蹤會因時間差錯亂。
.PARAMETER NtpServers
    公司 NTP server 清單 (多個用逗號), 預設 'ntp1.corp.local,ntp2.corp.local'。
.PARAMETER DryRun
    只列出將執行的動作, 不實際套用。
#>
[CmdletBinding()]
param(
    [string[]]$NtpServers = @('ntp1.corp.local', 'ntp2.corp.local'),
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

Write-Host "`n=== 設定 NTP 時間同步 ===`n" -ForegroundColor Cyan

# 1. 啟動 W32Time 服務並設自動啟動
$svc = Get-Service -Name W32Time -ErrorAction SilentlyContinue
if (-not $svc) {
    Write-Host "[fail] 找不到 W32Time 服務" -ForegroundColor Red
    exit 1
}

if ($DryRun) {
    Write-Host "[dry ] Set-Service W32Time -StartupType Automatic; Start-Service W32Time"
} else {
    Set-Service -Name W32Time -StartupType Automatic
    if ($svc.Status -ne 'Running') {
        Start-Service -Name W32Time
    }
    Write-Host "[ok  ] W32Time 服務啟動 + 自動啟動"
}

# 2. 設定 NTP server 清單
$peerList = ($NtpServers | ForEach-Object { "$_,0x9" }) -join ' '
$cmd = "w32tm /config /manualpeerlist:`"$peerList`" /syncfromflags:manual /reliable:yes /update"
Write-Host "[exec] $cmd"
if (-not $DryRun) {
    Invoke-Expression $cmd
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[fail] w32tm 設定失敗 (exit=$LASTEXITCODE)" -ForegroundColor Red
        exit 1
    }
}

# 3. 重啟服務套用設定
if (-not $DryRun) {
    Restart-Service W32Time
    Start-Sleep -Seconds 3
}

# 4. 強制同步
if (-not $DryRun) {
    & w32tm /resync /force | Out-Null
    Write-Host "[ok  ] 強制同步完成"
}

# 5. 驗證
if (-not $DryRun) {
    Write-Host "`n--- 同步狀態 ---" -ForegroundColor Cyan
    & w32tm /query /status
    Write-Host "`n--- NTP Peer ---" -ForegroundColor Cyan
    & w32tm /query /peers
}

Write-Host "`nNTP 設定完成。建議: 部署後 24 小時內檢查時間漂移 (與 PAM/AP/SIEM 對時)。" -ForegroundColor Green
