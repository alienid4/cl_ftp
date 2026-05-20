<#
.SYNOPSIS
    建立 D:\DataExchange (業務檔) + D:\_portal (系統檔) 目錄結構。
.DESCRIPTION
    依規畫建立各部門 inbound / pending / outbound / archive / error 五個子目錄
    (在 DataRoot 下), 以及 Portal 工作目錄 (獨立 PortalRoot, 對齊主管圖 / SQL schema)。
    預設部門 = HR / FIN / OPS, 可用 -Departments 覆蓋。
.PARAMETER Departments
    部門代碼陣列, 預設 'HR','FIN','OPS'。
.PARAMETER DataRoot
    業務檔根目錄, 預設 D:\DataExchange。
.PARAMETER PortalRoot
    Portal 系統檔根目錄 (獨立於 DataRoot), 預設 D:\_portal。
    對齊 sql\01_create_db.sql 的 FILENAME 'D:\_portal\db\FileExchangeAudit.mdf'。
.PARAMETER DryRun
    只列出將建立的目錄, 不實際建立。
.NOTES
    v1.0.0.9: 拆 DataRoot (業務) + PortalRoot (系統) 兩個獨立目錄
              對應規畫文件主管圖與 sql schema 的真實路徑
#>
[CmdletBinding()]
param(
    [string[]]$Departments = @('HR','FIN','OPS'),
    [string]$DataRoot = 'D:\DataExchange',
    [string]$PortalRoot = 'D:\_portal',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$subdirs = @('inbound','pending','outbound','archive','error')
$portalDirs = @('app','logs','db','scripts','backups','ftps_pasv')

# PS 5.1 compat: method-call argument 內呼叫 cmdlet 必須用雙括號包起來
$paths = [System.Collections.Generic.List[string]]::new()

# 業務檔目錄 (D:\DataExchange)
$paths.Add($DataRoot)
foreach ($d in $Departments) {
    $deptPath = Join-Path $DataRoot $d
    $paths.Add($deptPath)
    foreach ($s in $subdirs) {
        $paths.Add( (Join-Path $deptPath $s) )
    }
}

# samba 部門下載區 (對齊規畫文件)
$sambaPath = Join-Path $DataRoot 'samba'
$paths.Add($sambaPath)

# Portal 系統檔目錄 (D:\_portal, 獨立於 DataRoot)
$paths.Add($PortalRoot)
foreach ($p in $portalDirs) {
    $paths.Add( (Join-Path $PortalRoot $p) )
}

Write-Host "`n=== 建立目錄結構 ===`n" -ForegroundColor Cyan
Write-Host "DataRoot:   $DataRoot   (業務檔)" -ForegroundColor DarkCyan
Write-Host "PortalRoot: $PortalRoot (系統檔, 對齊 sql schema)" -ForegroundColor DarkCyan
Write-Host ""

foreach ($p in $paths) {
    if (Test-Path $p) {
        Write-Host "[skip] $p (已存在)"
    } elseif ($DryRun) {
        Write-Host "[dry ] $p"
    } else {
        New-Item -Path $p -ItemType Directory -Force | Out-Null
        Write-Host "[ok  ] $p"
    }
}

Write-Host "`n目錄結構建立完成。下一步: 02_setup_ntfs_acl.ps1" -ForegroundColor Green
