<#
.SYNOPSIS
    安裝 FSRM (File Server Resource Manager) 並設定 samba 各部門配額。
.DESCRIPTION
    對齊主管圖「容量使用監控」要求, 限制各部門 samba 目錄上限,
    超過閾值寄信告警, 接近滿時阻止寫入。
.PARAMETER Departments
    部門代碼 (對應 samba 子目錄), 預設 'architecture','hr','finance','security'。
.PARAMETER QuotaGB
    每部門配額 GB, 預設 50。
.PARAMETER WarnPercent
    警告閾值 (百分比), 預設 80。
.PARAMETER DryRun
    只列出將執行的動作, 不實際套用。
#>
[CmdletBinding()]
param(
    [string[]]$Departments = @('architecture', 'hr', 'finance', 'security'),
    [int]$QuotaGB = 50,
    [int]$WarnPercent = 80,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

Write-Host "`n=== 設定 FSRM 部門配額 ===`n" -ForegroundColor Cyan

# 1. 安裝 FSRM
$fsrm = Get-WindowsFeature -Name FS-Resource-Manager
if ($fsrm.InstallState -ne 'Installed') {
    if ($DryRun) {
        Write-Host "[dry ] Install-WindowsFeature FS-Resource-Manager"
    } else {
        Install-WindowsFeature -Name FS-Resource-Manager -IncludeManagementTools | Out-Null
        Write-Host "[ok  ] FSRM 角色已安裝"
    }
} else {
    Write-Host "[skip] FSRM 已安裝"
}

# 2. 設定 SMTP (FSRM 告警寄信用)
if (-not $DryRun) {
    # 注意: 實際的 SMTP server 由 IT 提供
    Set-FsrmSetting -SmtpServer 'mail-relay.corp.local' `
        -FromEmailAddress 'sf-noreply@corp.local' `
        -AdminEmailAddress 'it-admin@corp.local' `
        -ErrorAction SilentlyContinue
    Write-Host "[ok  ] FSRM SMTP 設定"
}

# 3. 為每個部門建立配額
$quotaBytes = $QuotaGB * 1GB
$warnBytes = [int64]($quotaBytes * $WarnPercent / 100)

foreach ($d in $Departments) {
    $path = "D:\DataExchange\samba\$d"

    if (-not (Test-Path $path)) {
        Write-Host "[skip] $path 不存在, 跳過"
        continue
    }

    if ($DryRun) {
        Write-Host "[dry ] FsrmQuota $path : $QuotaGB GB ($WarnPercent% warn)"
        continue
    }

    # 移除既有同路徑配額
    $existing = Get-FsrmQuota -Path $path -ErrorAction SilentlyContinue
    if ($existing) {
        Remove-FsrmQuota -Path $path -Confirm:$false
    }

    # 建立配額 + 警告閾值
    $action = New-FsrmAction -Type Email `
        -MailTo '[Admin Email];[Quota Owner Email]' `
        -MailSubject "[SF] $d 配額警告: 已用 [Quota Used Percent]%" `
        -MailBody "samba 部門目錄 $d 已使用 [Quota Used] / [Quota Limit] ([Quota Used Percent]%)"

    $threshold = New-FsrmQuotaThreshold -Percentage $WarnPercent -Action $action

    New-FsrmQuota -Path $path -Size $quotaBytes -Threshold $threshold `
        -Description "$d 部門 samba 配額 ($QuotaGB GB)" | Out-Null

    Write-Host "[ok  ] $path : $QuotaGB GB (警告 $WarnPercent%)"
}

Write-Host "`nFSRM 配額設定完成。" -ForegroundColor Green
Write-Host "查詢配額: Get-FsrmQuota | Format-Table Path, Size, Usage -AutoSize" -ForegroundColor Yellow
