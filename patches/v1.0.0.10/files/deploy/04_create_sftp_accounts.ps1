<#
.SYNOPSIS
    建立部門 SFTP 共用帳號 sftp_<dept>。
.DESCRIPTION
    建立本機帳號 sftp_<dept>, 加入專屬群組 sftp_users, 設定密碼。
    密碼由 -Passwords 提供 (建議從 PAM / 安全管道取得), 或互動式輸入。
.PARAMETER Departments
    部門代碼陣列, 預設 'HR','FIN','OPS'。
.PARAMETER Passwords
    部門 -> 密碼的 hashtable, 例: @{ HR='Pwd1!...'; FIN='Pwd2!...' }
    未提供時改用互動式輸入。
.PARAMETER GroupName
    SFTP 帳號群組, 預設 sftp_users。
.PARAMETER DryRun
    只列出將執行的動作, 不實際套用。
.EXAMPLE
    .\04_create_sftp_accounts.ps1
    # 互動式輸入各部門密碼
.EXAMPLE
    $pw = @{ HR = (ConvertTo-SecureString 'XXX' -AsPlainText -Force) }
    .\04_create_sftp_accounts.ps1 -Passwords $pw
#>
[CmdletBinding()]
param(
    [string[]]$Departments = @('HR','FIN','OPS'),
    [hashtable]$Passwords,
    [string]$GroupName = 'sftp_users',
    [switch]$BatchMode,   # v1.0.0.10: 跳過互動式建帳號 (給 install_offline.ps1 用)
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

Write-Host "`n=== 建立 SFTP 部門共用帳號 ===`n" -ForegroundColor Cyan

# BatchMode: 跳過互動式建帳號, 之後手動跑
if ($BatchMode -and -not $Passwords) {
    Write-Host "[skip] -BatchMode + 未提供 -Passwords, 跳過建立 SFTP 帳號" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "→ 之後 PAM 接管 / AP 系統要接時, 手動跑:" -ForegroundColor Yellow
    Write-Host "    .\04_create_sftp_accounts.ps1"
    Write-Host "  (互動輸入 3 個部門密碼, 14 碼以上含複雜度)"
    Write-Host ""
    Write-Host "  或非互動式:"
    Write-Host "    `$pw = @{ HR = (Read-Host 'HR pw' -AsSecureString); ... }"
    Write-Host "    .\04_create_sftp_accounts.ps1 -Passwords `$pw"
    exit 0
}

# 1. 建立群組
if (-not (Get-LocalGroup -Name $GroupName -ErrorAction SilentlyContinue)) {
    if ($DryRun) {
        Write-Host "[dry ] New-LocalGroup $GroupName"
    } else {
        New-LocalGroup -Name $GroupName -Description 'SFTP department shared accounts' | Out-Null
        Write-Host "[ok  ] 建立群組 $GroupName"
    }
} else {
    Write-Host "[skip] 群組 $GroupName 已存在"
}

# 2. 逐部門建帳號
foreach ($d in $Departments) {
    $acct = "sftp_$($d.ToLower())"

    # 取得密碼
    $secPwd = $null
    if ($Passwords -and $Passwords.ContainsKey($d)) {
        $val = $Passwords[$d]
        if ($val -is [System.Security.SecureString]) {
            $secPwd = $val
        } else {
            $secPwd = ConvertTo-SecureString $val -AsPlainText -Force
        }
    } elseif (-not $DryRun) {
        $secPwd = Read-Host -Prompt "請輸入 $acct 密碼 (>=14 碼, 含複雜度)" -AsSecureString
    }

    if (Get-LocalUser -Name $acct -ErrorAction SilentlyContinue) {
        Write-Host "[skip] 帳號 $acct 已存在"
    } else {
        if ($DryRun) {
            Write-Host "[dry ] New-LocalUser $acct"
        } else {
            # Description 限制 <= 48 字元, 縮短避免 "Department: FIN..." (49 字元) 炸
            New-LocalUser -Name $acct -Password $secPwd `
                -FullName "SFTP shared account for $d" `
                -Description "SFTP $d dept account (no interactive logon)" `
                -PasswordNeverExpires:$false `
                -UserMayNotChangePassword:$false | Out-Null
            Write-Host "[ok  ] 建立帳號 $acct"
        }
    }

    # 加入群組
    if (-not $DryRun) {
        $member = Get-LocalGroupMember -Group $GroupName -Member $acct -ErrorAction SilentlyContinue
        if (-not $member) {
            Add-LocalGroupMember -Group $GroupName -Member $acct
            Write-Host "[ok  ] $acct 加入群組 $GroupName"
        }

        # 拒絕互動式登入 (僅允許網路登入做 SFTP)
        # 透過 secedit / GPO 較完整, 此處先用 ntrights.exe 替代寫法或 GPO 處理
        # 此處留註記; 實際在 07_setup_gpo_policy.ps1 統一設
    }
}

Write-Host "`nSFTP 帳號建立完成。下一步: 05_setup_firewall.ps1" -ForegroundColor Green
Write-Host "提醒: 帳號預設可互動登入, 將於 07_setup_gpo_policy.ps1 收緊為僅網路登入" -ForegroundColor Yellow
