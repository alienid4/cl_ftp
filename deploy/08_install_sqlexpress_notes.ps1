<#
.SYNOPSIS
    SQL Server Express 安裝提示與 AuditLog DB 建立。
.DESCRIPTION
    SQL Server Express 須從 Microsoft 下載安裝程式 (互動式精靈), 本腳本不自動安裝,
    而是檢查是否已安裝, 若已安裝則執行 sql\01_create_db.sql 建立 AuditLog 資料庫。
.PARAMETER InstanceName
    SQL Server Express 執行個體名稱, 預設 SQLEXPRESS。
.PARAMETER DbName
    AuditLog 資料庫名稱, 預設 FileExchangeAudit。
.PARAMETER SqlScript
    SQL schema 檔, 預設 ..\sql\01_create_db.sql。
.PARAMETER DryRun
    只列出將執行的動作, 不實際套用。
#>
[CmdletBinding()]
param(
    [string]$InstanceName = 'SQLEXPRESS',
    [string]$DbName       = 'FileExchangeAudit',
    [string]$SqlScript    = (Join-Path $PSScriptRoot '..\sql\01_create_db.sql'),
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

Write-Host "`n=== SQL Server Express 設定 ===`n" -ForegroundColor Cyan

# 1. 檢查 SQL Server Express 是否安裝
$svc = Get-Service -Name "MSSQL`$$InstanceName" -ErrorAction SilentlyContinue
if (-not $svc) {
    Write-Host "[fail] 未偵測到 SQL Server Express 服務 (MSSQL`$$InstanceName)" -ForegroundColor Red
    Write-Host ""
    Write-Host "請先手動安裝 SQL Server 2022 Express:" -ForegroundColor Yellow
    Write-Host "  https://www.microsoft.com/en-us/sql-server/sql-server-downloads"
    Write-Host ""
    Write-Host "安裝重點:"
    Write-Host "  - 執行個體名稱: $InstanceName"
    Write-Host "  - 驗證模式: Windows 驗證 (建議) 或 混合模式"
    Write-Host "  - 資料庫路徑: D:\DataExchange\_portal\db\"
    Write-Host "  - 排序規則: Chinese_Taiwan_Stroke_CI_AS (或公司標準)"
    Write-Host "  - 啟用 TCP/IP 通訊協定"
    Write-Host ""
    Write-Host "安裝完成後重跑此腳本。"
    exit 1
}

Write-Host "[ok  ] 偵測到 SQL Server 服務: $($svc.Name), 狀態: $($svc.Status)"

if ($svc.Status -ne 'Running') {
    if ($DryRun) {
        Write-Host "[dry ] Start-Service $($svc.Name)"
    } else {
        Start-Service $svc.Name
        Write-Host "[ok  ] 已啟動 $($svc.Name)"
    }
}

# 2. 確認 sqlcmd 可用
$sqlcmd = Get-Command sqlcmd.exe -ErrorAction SilentlyContinue
if (-not $sqlcmd) {
    Write-Host "[fail] 找不到 sqlcmd.exe, 請安裝 SqlClient Tools 或 Command Line Utilities" -ForegroundColor Red
    Write-Host "  https://learn.microsoft.com/sql/tools/sqlcmd-utility"
    exit 1
}

# 3. 執行 schema 建立
if (-not (Test-Path $SqlScript)) {
    Write-Host "[fail] 找不到 SQL 腳本: $SqlScript" -ForegroundColor Red
    exit 1
}

$server = ".\$InstanceName"
Write-Host "`n預計對 $server 執行 $SqlScript"

if ($DryRun) {
    Write-Host "[dry ] sqlcmd -S $server -E -i $SqlScript"
} else {
    & sqlcmd -S $server -E -i $SqlScript
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[ok  ] DB schema 建立完成: $DbName" -ForegroundColor Green
    } else {
        Write-Host "[fail] sqlcmd 執行失敗 (exit=$LASTEXITCODE)" -ForegroundColor Red
        exit 1
    }
}

Write-Host "`nSQL Server Express 設定完成。下一步: 09_setup_portal.ps1" -ForegroundColor Green
