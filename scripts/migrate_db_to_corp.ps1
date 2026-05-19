<#
.SYNOPSIS
    [第二階段] 把 AuditLog 從本機 SQL Express 遷移到公司 MS SQL Server。
.DESCRIPTION
    將來 (第二階段, 公司 DBA 給了正式 DB 之後), 跑這支腳本一次性把資料搬過去。

    流程:
    1. 確認連線 (本機 Express + 公司 DB 都通)
    2. 停止 Portal 服務 (避免遷移期間寫入)
    3. 在公司 DB 建立 schema (跑 sql/01_create_db.sql)
    4. 用 bcp 匯出 Express → 匯入公司 DB
    5. 驗證行數一致
    6. 改 appsettings.json connection string
    7. 重啟 Portal
    8. 驗證新連線
    9. 標記舊 Express DB 為 readonly (備援, 不刪)

    安全機制:
    - 預設 -DryRun
    - 加 -Confirm 才實際執行
.PARAMETER CorpDBServer
    公司 DB Server, 例: 'corp-sql01.internal,1433'
.PARAMETER CorpDBName
    DB 名稱, 預設 'FileExchangeAudit'。
.PARAMETER ExpressInstance
    本機 SQL Express 連線, 預設 '.\SQLEXPRESS'。
.PARAMETER ExportDir
    bcp 匯出檔暫存目錄, 預設 'D:\_portal\backups\migration'。
.PARAMETER Confirm
    確認執行 (不加會以 dry-run 模式跑)。
.EXAMPLE
    # 預演
    .\migrate_db_to_corp.ps1 -CorpDBServer 'corp-sql01.internal,1433'
.EXAMPLE
    # 實際執行
    .\migrate_db_to_corp.ps1 -CorpDBServer 'corp-sql01.internal,1433' -Confirm
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$CorpDBServer,
    [string]$CorpDBName = 'FileExchangeAudit',
    [string]$ExpressInstance = '.\SQLEXPRESS',
    [string]$ExportDir = 'D:\_portal\backups\migration',
    [switch]$Confirm
)

$ErrorActionPreference = 'Stop'
$DryRun = -not $Confirm

function Step {
    param([int]$N, [string]$Title)
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host (" Step {0}: {1}" -f $N, $Title) -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Cyan
}

Write-Host "`n=== AuditLog 遷移: SQL Express → 公司 MS SQL Server ===" -ForegroundColor Cyan
Write-Host "Source: $ExpressInstance / FileExchangeAudit"
Write-Host "Target: $CorpDBServer / $CorpDBName"
Write-Host "模式  : $(if ($DryRun) { 'DRY-RUN (預演)' } else { '正式執行' })" -ForegroundColor $(if ($DryRun) { 'Yellow' } else { 'Red' })

if (-not (Test-Path $ExportDir)) {
    if (-not $DryRun) { New-Item -Path $ExportDir -ItemType Directory -Force | Out-Null }
}

# ===== Step 1: 連線測試 =====
Step 1 "連線測試"

function Test-SqlConnection {
    param([string]$Server)
    try {
        $conn = New-Object System.Data.SqlClient.SqlConnection("Server=$Server;Integrated Security=True;Connection Timeout=5")
        $conn.Open()
        $conn.Close()
        return $true
    } catch { return $false }
}

if (Test-SqlConnection $ExpressInstance) {
    Write-Host "[ok] 本機 Express 連線正常" -ForegroundColor Green
} else {
    Write-Host "[FAIL] 無法連線本機 Express ($ExpressInstance)" -ForegroundColor Red
    exit 1
}

if (Test-SqlConnection $CorpDBServer) {
    Write-Host "[ok] 公司 DB 連線正常" -ForegroundColor Green
} else {
    Write-Host "[FAIL] 無法連線公司 DB ($CorpDBServer)" -ForegroundColor Red
    Write-Host "  請確認:" -ForegroundColor Yellow
    Write-Host "  - 防火牆 TCP 1433 已開"
    Write-Host "  - SF 機器帳號或當前使用者有 db_datareader / db_datawriter 權限"
    Write-Host "  - DB 已建立 (DBA 申請完)"
    exit 1
}

# ===== Step 2: 停止 Portal =====
Step 2 "停止 Portal 服務 (避免遷移時寫入)"
$svc = Get-Service -Name 'FileExchangePortal' -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -eq 'Running') {
    Write-Host "[exec] Stop-Service FileExchangePortal"
    if (-not $DryRun) {
        Stop-Service FileExchangePortal
        Start-Sleep -Seconds 3
        Write-Host "[ok] Portal 已停止" -ForegroundColor Green
    }
} else {
    Write-Host "[info] Portal 未運行或不存在" -ForegroundColor Yellow
}

# ===== Step 3: 在公司 DB 建立 schema =====
Step 3 "在公司 DB 建立 AuditLog schema"
$schemaSQL = Join-Path $PSScriptRoot '..\sql\01_create_db.sql'
if (Test-Path $schemaSQL) {
    Write-Host "[exec] sqlcmd -S $CorpDBServer -E -d $CorpDBName -i $schemaSQL"
    if (-not $DryRun) {
        & sqlcmd -S $CorpDBServer -E -d $CorpDBName -i $schemaSQL
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[FAIL] Schema 建立失敗" -ForegroundColor Red
            exit 1
        }
        Write-Host "[ok] Schema 建立完成" -ForegroundColor Green
    }
} else {
    Write-Host "[FAIL] 找不到 schema 檔: $schemaSQL" -ForegroundColor Red
    exit 1
}

# ===== Step 4: bcp 匯出 → 匯入 =====
Step 4 "資料遷移 (bcp out → bcp in)"

$bcpFile = Join-Path $ExportDir "AuditLog_$(Get-Date -Format yyyyMMdd_HHmmss).dat"
$bcpFmt  = Join-Path $ExportDir 'AuditLog.fmt'

Write-Host "[exec] bcp out: $bcpFile"
if (-not $DryRun) {
    & bcp 'FileExchangeAudit.dbo.AuditLog' out $bcpFile -S $ExpressInstance -T -n
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[FAIL] bcp out 失敗" -ForegroundColor Red
        exit 1
    }
    $size = (Get-Item $bcpFile).Length / 1MB
    Write-Host ("[ok] 匯出 {0:N1} MB" -f $size) -ForegroundColor Green
}

Write-Host "[exec] bcp in: 公司 DB"
if (-not $DryRun) {
    & bcp "$CorpDBName.dbo.AuditLog" in $bcpFile -S $CorpDBServer -T -n -E
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[FAIL] bcp in 失敗" -ForegroundColor Red
        exit 1
    }
    Write-Host "[ok] 匯入完成" -ForegroundColor Green
}

# ===== Step 5: 驗證行數 =====
Step 5 "驗證: Source vs Target 行數一致"

function Get-RowCount {
    param([string]$Server, [string]$Db)
    $sql = "SELECT COUNT(*) FROM $Db.dbo.AuditLog"
    $result = & sqlcmd -S $Server -E -Q $sql -h -1 -W 2>$null
    return [int]($result -split "`n" | Where-Object { $_ -match '^\d+$' } | Select-Object -First 1)
}

if (-not $DryRun) {
    $srcCount = Get-RowCount $ExpressInstance 'FileExchangeAudit'
    $dstCount = Get-RowCount $CorpDBServer $CorpDBName
    Write-Host "  Source (Express) : $srcCount 筆"
    Write-Host "  Target (公司 DB) : $dstCount 筆"

    if ($srcCount -eq $dstCount -and $srcCount -gt 0) {
        Write-Host "[ok] 行數一致 ✓" -ForegroundColor Green
    } elseif ($srcCount -eq 0 -and $dstCount -eq 0) {
        Write-Host "[warn] 兩邊都 0 筆 (新環境?)" -ForegroundColor Yellow
    } else {
        Write-Host "[FAIL] 行數不一致, 中止遷移" -ForegroundColor Red
        Write-Host "      → 重啟 Portal 並使用原 Express DB" -ForegroundColor Yellow
        Start-Service FileExchangePortal -ErrorAction SilentlyContinue
        exit 1
    }
}

# ===== Step 6: 改 appsettings.json =====
Step 6 "更新 Portal connection string"
$appSettings = 'D:\_portal\app\appsettings.json'
$newConnStr = "Server=$CorpDBServer;Database=$CorpDBName;Integrated Security=True;TrustServerCertificate=True"

if (Test-Path $appSettings) {
    # 備份
    if (-not $DryRun) {
        Copy-Item $appSettings "$appSettings.bak.$(Get-Date -Format yyyyMMdd_HHmmss)" -Force
    }

    $config = Get-Content $appSettings -Raw | ConvertFrom-Json
    $config | Add-Member -NotePropertyName 'DbMode' -NotePropertyValue 'CorpDB' -Force
    $config | Add-Member -NotePropertyName 'ConnectionString' -NotePropertyValue $newConnStr -Force
    $config | Add-Member -NotePropertyName 'DbServer' -NotePropertyValue $CorpDBServer -Force
    $config | Add-Member -NotePropertyName 'DbName' -NotePropertyValue $CorpDBName -Force
    $config | Add-Member -NotePropertyName 'MigratedAt' -NotePropertyValue (Get-Date).ToString('o') -Force

    if (-not $DryRun) {
        $config | ConvertTo-Json | Set-Content -Path $appSettings -Encoding UTF8
        Write-Host "[ok] appsettings.json 已更新" -ForegroundColor Green
    } else {
        Write-Host "[dry] 將寫入 $appSettings"
    }
    Write-Host "      New ConnString: $newConnStr"
}

# ===== Step 7: 重啟 Portal =====
Step 7 "重啟 Portal 使用新 DB"
if (-not $DryRun) {
    Start-Service FileExchangePortal
    Start-Sleep -Seconds 5
    $svc = Get-Service FileExchangePortal
    if ($svc.Status -eq 'Running') {
        Write-Host "[ok] Portal 已啟動, 連到公司 DB" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] Portal 啟動失敗, 請檢查 log" -ForegroundColor Red
    }
}

# ===== Step 8: 標記舊 Express DB readonly (備援) =====
Step 8 "舊 Express DB 改為唯讀 (備援 30 天後可刪)"
$readonlySQL = "ALTER DATABASE FileExchangeAudit SET READ_ONLY WITH ROLLBACK IMMEDIATE"
Write-Host "[exec] $readonlySQL"
if (-not $DryRun) {
    & sqlcmd -S $ExpressInstance -E -Q $readonlySQL
    Write-Host "[ok] 舊 DB 標記 READ_ONLY (備援用, 確認穩定後可手動 DROP)" -ForegroundColor Green
} else {
    Write-Host "[dry] (skip)"
}

# ===== 完成 =====
Write-Host ""
Write-Host ("=" * 60) -ForegroundColor Green
Write-Host " 第二階段遷移完成" -ForegroundColor Green
Write-Host ("=" * 60) -ForegroundColor Green
Write-Host "  Portal 現在使用: $CorpDBServer / $CorpDBName"
Write-Host "  舊 Express DB  : 唯讀 (備援)"
Write-Host ""
Write-Host "驗證:"
Write-Host "  1. 開瀏覽器看 Portal 稽核查詢頁, 確認資料還在"
Write-Host "  2. 跑 .\scripts\health_check.ps1 確認 DB 連線 OK"
Write-Host "  3. 觀察 1~2 週, 確認穩定後可在公司 DBA 那邊將舊 Express DB DROP"
Write-Host ""
if ($DryRun) {
    Write-Host "⚠️ 上述為 DRY-RUN 預演, 實際執行請加 -Confirm" -ForegroundColor Yellow
}
