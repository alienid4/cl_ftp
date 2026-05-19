<#
.SYNOPSIS
    設定 D:\DataExchange 的 NTFS ACL。
.DESCRIPTION
    原則:
    - 每個部門目錄只給該部門 SFTP 共用帳號 (sftp_<dept>) 讀寫
    - Portal 應用程式池身分 (IIS AppPool\FileExchangePortal) 對所有部門目錄讀寫
    - _portal\db 只給 NT SERVICE\MSSQL$SQLEXPRESS (或 SQL 服務帳號) 讀寫
    - 移除 Users / Everyone / Authenticated Users 的繼承權限
    - 部門間互相不可讀
.PARAMETER Departments
    部門代碼陣列, 預設 'HR','FIN','OPS'。
.PARAMETER Root
    根目錄, 預設 D:\DataExchange。
.PARAMETER PortalAppPool
    Portal IIS App Pool 名稱, 預設 FileExchangePortal。
.PARAMETER SqlServiceAccount
    SQL Server 服務帳號, 預設 NT SERVICE\MSSQL$SQLEXPRESS。
.PARAMETER DryRun
    只列出將執行的 ACL 變更, 不實際套用。
#>
[CmdletBinding()]
param(
    [string[]]$Departments = @('HR','FIN','OPS'),
    [string]$Root = 'D:\DataExchange',
    [string]$PortalAppPool = 'FileExchangePortal',
    [string]$SqlServiceAccount = 'NT SERVICE\MSSQL$SQLEXPRESS',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Set-FolderAcl {
    param(
        [string]$Path,
        [hashtable]$Permissions,   # @{ 'Identity' = 'FullControl' | 'Modify' | 'ReadAndExecute' }
        [bool]$RemoveInheritance = $true,
        [string[]]$Strip = @('BUILTIN\Users','Everyone','Authenticated Users')
    )

    if (-not (Test-Path $Path)) {
        Write-Host "[skip] $Path (路徑不存在)" -ForegroundColor Yellow
        return
    }

    if ($DryRun) {
        Write-Host "[dry ] $Path -> $($Permissions.Keys -join ', ')"
        return
    }

    $acl = Get-Acl $Path

    if ($RemoveInheritance) {
        $acl.SetAccessRuleProtection($true, $false)   # 保護, 不繼承, 不複製父原則
    }

    # 移除指定的繼承權限
    foreach ($s in $Strip) {
        $acl.Access | Where-Object { $_.IdentityReference.Value -like "*$s*" } | ForEach-Object {
            $acl.RemoveAccessRule($_) | Out-Null
        }
    }

    # 加入新權限
    foreach ($identity in $Permissions.Keys) {
        $rights = $Permissions[$identity]
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $identity,
            $rights,
            'ContainerInherit,ObjectInherit',
            'None',
            'Allow'
        )
        try {
            $acl.AddAccessRule($rule)
        } catch {
            Write-Host "[warn] 無法加入 $identity : $_" -ForegroundColor Yellow
        }
    }

    Set-Acl -Path $Path -AclObject $acl
    Write-Host "[ok  ] $Path  ($($Permissions.Keys -join ', '))"
}

Write-Host "`n=== 設定 NTFS ACL ===`n" -ForegroundColor Cyan

# 根目錄: 只給 Administrators 與 SYSTEM, Portal AppPool 不繼承到這層
Set-FolderAcl -Path $Root -Permissions @{
    'BUILTIN\Administrators' = 'FullControl'
    'NT AUTHORITY\SYSTEM'    = 'FullControl'
}

foreach ($d in $Departments) {
    $deptPath = Join-Path $Root $d
    $sftpAcct = "$env:COMPUTERNAME\sftp_$($d.ToLower())"

    # 部門根: 該部門 SFTP 帳號 + Portal AppPool 可讀寫
    Set-FolderAcl -Path $deptPath -Permissions @{
        'BUILTIN\Administrators' = 'FullControl'
        'NT AUTHORITY\SYSTEM'    = 'FullControl'
        $sftpAcct                = 'Modify'
        "IIS AppPool\$PortalAppPool" = 'Modify'
    }
}

# Portal 目錄
$portalPath = Join-Path $Root '_portal'
Set-FolderAcl -Path $portalPath -Permissions @{
    'BUILTIN\Administrators' = 'FullControl'
    'NT AUTHORITY\SYSTEM'    = 'FullControl'
    "IIS AppPool\$PortalAppPool" = 'Modify'
}

# _portal\db 只給 SQL 服務帳號
$dbPath = Join-Path $portalPath 'db'
Set-FolderAcl -Path $dbPath -Permissions @{
    'BUILTIN\Administrators' = 'FullControl'
    'NT AUTHORITY\SYSTEM'    = 'FullControl'
    $SqlServiceAccount       = 'FullControl'
}

Write-Host "`nNTFS ACL 設定完成。注意: SFTP 部門帳號需先建立 (見 04_create_sftp_accounts.ps1)" -ForegroundColor Green
Write-Host "若先跑此腳本而帳號未建, 會有 [warn] 訊息, 待帳號建立後重跑即可。" -ForegroundColor Yellow
