<#
.SYNOPSIS
    安裝 Windows Server Backup 並設定資料目錄備份排程。
.DESCRIPTION
    對齊主管圖「備份與保存」要求, 每日凌晨 01:00 備份:
    - D:\DataExchange (上傳資料 + samba)
    - D:\_portal\db (AuditLog DB)
    - D:\_portal\app (Portal 程式碼)
    備份目標: 異地備份伺服器 SMB share, 保留 30 天。
.PARAMETER BackupTarget
    備份目的 (UNC 或本機磁碟), 例: '\\backup-srv\sf-backup'
.PARAMETER BackupTime
    每日備份時間, 預設 01:00。
.PARAMETER RetentionDays
    保留天數, 預設 30。
.PARAMETER DryRun
    只列出將執行的動作, 不實際套用。
#>
[CmdletBinding()]
param(
    [string]$BackupTarget = '\\backup-srv\sf-backup',
    [string]$BackupTime = '01:00',
    [int]$RetentionDays = 30,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

Write-Host "`n=== 設定 Windows Server Backup ===`n" -ForegroundColor Cyan

# 1. 安裝 Windows Server Backup 角色
$wsb = Get-WindowsFeature -Name Windows-Server-Backup
if ($wsb.InstallState -ne 'Installed') {
    if ($DryRun) {
        Write-Host "[dry ] Install-WindowsFeature Windows-Server-Backup"
    } else {
        Install-WindowsFeature -Name Windows-Server-Backup -IncludeManagementTools | Out-Null
        Write-Host "[ok  ] Windows Server Backup 已安裝"
    }
} else {
    Write-Host "[skip] Windows Server Backup 已安裝"
}

# 2. 建立排程工作 (用 wbadmin)
$taskName = 'SF_DailyBackup'
$scriptDir = 'D:\_portal\scripts'
$backupScript = Join-Path $scriptDir 'run_daily_backup.ps1'

if (-not (Test-Path $scriptDir)) {
    if (-not $DryRun) {
        New-Item -Path $scriptDir -ItemType Directory -Force | Out-Null
    }
}

# 3. 產生實際備份腳本
$backupCode = @"
# SF 每日備份腳本 (由 15_setup_backup.ps1 產生)
`$ErrorActionPreference = 'Continue'
`$logFile = 'D:\_portal\logs\backup_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.log'
`$target = '$BackupTarget'

Start-Transcript -Path `$logFile -Append

Write-Output ('=== 備份開始: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ===')

# 備份範圍
`$sources = @(
    'D:\DataExchange',
    'D:\_portal\db',
    'D:\_portal\app',
    'D:\_portal\backups'
)

`$dateTag = Get-Date -Format 'yyyyMMdd'
`$backupRoot = Join-Path `$target ('sf_' + `$dateTag)

if (-not (Test-Path `$backupRoot)) {
    New-Item -Path `$backupRoot -ItemType Directory -Force | Out-Null
}

foreach (`$src in `$sources) {
    `$dst = Join-Path `$backupRoot (Split-Path `$src -Leaf)
    Write-Output ('Copying ' + `$src + ' -> ' + `$dst)
    & robocopy `$src `$dst /MIR /R:2 /W:5 /NP /NS /NJH /LOG+:`$logFile
}

# 保留天數清理
`$cutoff = (Get-Date).AddDays(-$RetentionDays)
Get-ChildItem `$target -Directory -Filter 'sf_*' | Where-Object {
    `$_.LastWriteTime -lt `$cutoff
} | ForEach-Object {
    Write-Output ('Removing old backup: ' + `$_.FullName)
    Remove-Item `$_.FullName -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output ('=== 備份結束: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ===')
Stop-Transcript
"@

if ($DryRun) {
    Write-Host "[dry ] Write backup script to $backupScript"
} else {
    Set-Content -Path $backupScript -Value $backupCode -Encoding UTF8
    Write-Host "[ok  ] 備份腳本已產生: $backupScript"
}

# 4. 建立排程工作
if ($DryRun) {
    Write-Host "[dry ] Register-ScheduledTask $taskName at $BackupTime"
} else {
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$backupScript`""
    $trigger = New-ScheduledTaskTrigger -Daily -At $BackupTime
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable `
        -RunOnlyIfNetworkAvailable -DontStopIfGoingOnBatteries

    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
        -Principal $principal -Settings $settings `
        -Description "SF 每日資料 + DB + Portal 備份, 保留 $RetentionDays 天" | Out-Null

    Write-Host "[ok  ] 排程工作 $taskName 已建立 (每日 $BackupTime)"
}

# 5. 設定備份備份目標的權限提示
Write-Host ""
Write-Host "重要提醒:" -ForegroundColor Yellow
Write-Host "  1. 確認 SYSTEM 帳號對 $BackupTarget 有寫入權"
Write-Host "  2. 若 BackupTarget 是 UNC, 需透過 服務帳號 或 cmdkey 設定認證"
Write-Host "  3. 建議手動執行一次驗證: powershell -File $backupScript"

Write-Host "`nWindows Server Backup 設定完成。" -ForegroundColor Green
