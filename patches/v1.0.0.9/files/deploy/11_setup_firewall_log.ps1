<#
.SYNOPSIS
    啟用 Windows Firewall 連線紀錄 (對齊主管圖「防火牆連線紀錄」要求)。
.DESCRIPTION
    Windows Firewall 預設「不記錄」連線, 主管圖要求此項稽核, 故啟用 log。
    輸出檔 C:\Windows\System32\LogFiles\Firewall\pfirewall.log, 預設大小 4096 KB。
    若要長期保存, 建議排程把這檔搬到 D:\_portal\logs\firewall\YYYYMMDD.log。
.PARAMETER LogMaxKb
    Log 檔最大大小 (KB), 預設 32768 (32 MB)。
.PARAMETER DryRun
    只列出將執行的動作, 不實際套用。
#>
[CmdletBinding()]
param(
    [int]$LogMaxKb = 32768,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

Write-Host "`n=== 啟用 Windows Firewall 連線紀錄 ===`n" -ForegroundColor Cyan

$profiles = @('Domain', 'Private', 'Public')

foreach ($p in $profiles) {
    Write-Host "[exec] Set firewall log: profile=$p, allowed=true, dropped=true, size=${LogMaxKb}KB"
    if (-not $DryRun) {
        # PS 5.1: -LogAllowed/-LogBlocked 要 GpoBoolean enum (True/False/NotConfigured),
        # 用字串 'True' 在某些版本 OK, 但 Set-NetFirewallProfile 在 Server 2022 PS 5.1
        # 比較挑, 改用 enum 物件比較穩
        try {
            Set-NetFirewallProfile -Profile $p `
                -LogAllowed ([Microsoft.PowerShell.Cmdletization.GeneratedTypes.NetFirewall.GpoBoolean]::True) `
                -LogBlocked ([Microsoft.PowerShell.Cmdletization.GeneratedTypes.NetFirewall.GpoBoolean]::True) `
                -LogMaxSizeKilobytes $LogMaxKb `
                -LogFileName '%SystemRoot%\System32\LogFiles\Firewall\pfirewall.log' `
                -ErrorAction Stop
            Write-Host "[ok  ] $p profile 防火牆紀錄已啟用" -ForegroundColor Green
        } catch {
            # Fallback: 用 netsh (老 API, 比較通用)
            Write-Host "[warn] Set-NetFirewallProfile 失敗, fallback 用 netsh" -ForegroundColor Yellow
            $netshProfile = switch ($p) { 'Domain' {'domain'}; 'Private' {'private'}; 'Public' {'public'} }
            $logPath = "$env:SystemRoot\System32\LogFiles\Firewall\pfirewall.log"
            & netsh advfirewall set $netshProfile`profile logging filename "$logPath" 2>&1 | Out-Null
            & netsh advfirewall set $netshProfile`profile logging maxfilesize $LogMaxKb 2>&1 | Out-Null
            & netsh advfirewall set $netshProfile`profile logging allowedconnections enable 2>&1 | Out-Null
            & netsh advfirewall set $netshProfile`profile logging droppedconnections enable 2>&1 | Out-Null
            Write-Host "[ok  ] $p profile 防火牆紀錄已啟用 (via netsh)" -ForegroundColor Green
        }
    }
}

# 確認設定
if (-not $DryRun) {
    Write-Host "`n--- 當前設定 ---" -ForegroundColor Cyan
    Get-NetFirewallProfile | Select-Object Name, LogAllowed, LogBlocked, LogMaxSizeKilobytes, LogFileName | Format-Table -AutoSize
}

Write-Host "`n防火牆紀錄已啟用。log 路徑: C:\Windows\System32\LogFiles\Firewall\pfirewall.log" -ForegroundColor Green
Write-Host "建議: 設一支排程腳本每日將 log 搬到 D:\_portal\logs\firewall\ 長期保存" -ForegroundColor Yellow
