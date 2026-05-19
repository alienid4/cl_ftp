<#
.SYNOPSIS
    建立 D:\DataExchange 目錄結構。
.DESCRIPTION
    依規畫建立各部門 inbound / pending / outbound / archive / error 五個子目錄,
    以及 _portal 工作目錄。預設部門 = HR / FIN / OPS, 可用 -Departments 覆蓋。
.PARAMETER Departments
    部門代碼陣列, 預設 'HR','FIN','OPS'。
.PARAMETER Root
    根目錄, 預設 D:\DataExchange。
.PARAMETER DryRun
    只列出將建立的目錄, 不實際建立。
#>
[CmdletBinding()]
param(
    [string[]]$Departments = @('HR','FIN','OPS'),
    [string]$Root = 'D:\DataExchange',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$subdirs = @('inbound','pending','outbound','archive','error')
$portalDirs = @('app','logs','db')

# PS 5.1 compat: method-call argument 內呼叫 cmdlet 必須用雙括號包起來
$paths = [System.Collections.Generic.List[string]]::new()
$paths.Add($Root)
foreach ($d in $Departments) {
    $deptPath = Join-Path $Root $d
    $paths.Add($deptPath)
    foreach ($s in $subdirs) {
        $paths.Add( (Join-Path $deptPath $s) )
    }
}
$portalPath = Join-Path $Root '_portal'
$paths.Add($portalPath)
foreach ($p in $portalDirs) {
    $paths.Add( (Join-Path $portalPath $p) )
}

Write-Host "`n=== 建立目錄結構 ===`n" -ForegroundColor Cyan
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
