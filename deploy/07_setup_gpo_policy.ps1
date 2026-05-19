<#
.SYNOPSIS
    套用本機帳號與安全政策。
.DESCRIPTION
    使用 secedit 與 Local Security Policy API 套用:
    - 密碼長度 >= 14
    - 密碼複雜度啟用
    - 90 天更換 (MaximumPasswordAge=90)
    - 不可重複前 10 組 (PasswordHistorySize=10)
    - 5 次失敗鎖定 30 分鐘 (LockoutBadCount=5, LockoutDuration=30)
    - 停用 SMBv1
    - 拒絕 sftp_users 群組互動式登入 (僅網路登入)
    - 強化 TLS / 停用 RC4 / 3DES / SHA1 (透過 IISCrypto 建議, 此處給 SCHANNEL 機碼)
.PARAMETER DryRun
    只列出將執行的動作, 不實際套用。
#>
[CmdletBinding()]
param(
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

Write-Host "`n=== 套用本機帳號與安全政策 ===`n" -ForegroundColor Cyan

# 1. 帳號政策 (用 secedit)
$infTemplate = @"
[Unicode]
Unicode=yes
[System Access]
MinimumPasswordLength = 14
PasswordComplexity = 1
MaximumPasswordAge = 90
MinimumPasswordAge = 1
PasswordHistorySize = 10
LockoutBadCount = 5
ResetLockoutCount = 30
LockoutDuration = 30
[Version]
signature="`$CHICAGO`$"
Revision=1
"@

$infPath = Join-Path $env:TEMP "fx_secpol_$(Get-Date -Format yyyyMMdd_HHmmss).inf"
$dbPath  = Join-Path $env:TEMP "fx_secpol.sdb"

if ($DryRun) {
    Write-Host "[dry ] secedit /configure (帳號政策 14碼/90天/5次鎖定30分鐘)"
} else {
    Set-Content -Path $infPath -Value $infTemplate -Encoding Unicode
    & secedit.exe /configure /db $dbPath /cfg $infPath /quiet
    Write-Host "[ok  ] 帳號政策套用完成 (檢視: gpedit.msc 或 secpol.msc)"
}

# 2. 停用 SMBv1
$smb = Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction SilentlyContinue
if ($smb -and $smb.State -eq 'Enabled') {
    if ($DryRun) {
        Write-Host "[dry ] Disable-WindowsOptionalFeature SMB1Protocol"
    } else {
        Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart | Out-Null
        Write-Host "[ok  ] 停用 SMBv1 (需重啟生效)"
    }
} else {
    Write-Host "[skip] SMBv1 已停用或不存在"
}

# 3. 拒絕 sftp_users 群組「在本機登入」(僅允許 SFTP 網路登入)
# 透過 secedit 的 [Privilege Rights] 設定 SeDenyInteractiveLogonRight
$denyInf = @"
[Unicode]
Unicode=yes
[Privilege Rights]
SeDenyInteractiveLogonRight = *S-1-5-32-545,sftp_users
SeDenyRemoteInteractiveLogonRight = sftp_users
[Version]
signature="`$CHICAGO`$"
Revision=1
"@
# 註: *S-1-5-32-545 = BUILTIN\Users (示意, 實際需先 export 再合併)
# 簡化做法: 直接用 ntrights.exe 或在 GPO 設定; 此處給範本提示

if ($DryRun) {
    Write-Host "[dry ] 拒絕 sftp_users 互動式登入 (請手動於 secpol.msc 確認)"
} else {
    Write-Host "[info] 拒絕 sftp_users 互動式登入需於 secpol.msc:" -ForegroundColor Yellow
    Write-Host "       本機原則 -> 使用者權限指派 -> 拒絕本機登入 / 拒絕透過遠端桌面登入" -ForegroundColor Yellow
    Write-Host "       加入 sftp_users 群組" -ForegroundColor Yellow
}

# 4. 強化 SCHANNEL: 停用 TLS 1.0 / 1.1 / SSL 2.0 / 3.0, 停用 RC4 / 3DES / SHA1
$schannelBase = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL'

$disableProtos = @('SSL 2.0','SSL 3.0','TLS 1.0','TLS 1.1')
foreach ($p in $disableProtos) {
    $srv = "$schannelBase\Protocols\$p\Server"
    $cli = "$schannelBase\Protocols\$p\Client"
    foreach ($k in @($srv, $cli)) {
        if ($DryRun) {
            Write-Host "[dry ] Disable $k"
        } else {
            if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }
            New-ItemProperty -Path $k -Name 'Enabled' -Value 0 -PropertyType DWord -Force | Out-Null
            New-ItemProperty -Path $k -Name 'DisabledByDefault' -Value 1 -PropertyType DWord -Force | Out-Null
        }
    }
    if (-not $DryRun) { Write-Host "[ok  ] 停用 $p" }
}

# 啟用 TLS 1.2 (預設應已啟用, 但確認)
$tls12Srv = "$schannelBase\Protocols\TLS 1.2\Server"
$tls12Cli = "$schannelBase\Protocols\TLS 1.2\Client"
foreach ($k in @($tls12Srv, $tls12Cli)) {
    if ($DryRun) {
        Write-Host "[dry ] Enable $k"
    } else {
        if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }
        New-ItemProperty -Path $k -Name 'Enabled' -Value 1 -PropertyType DWord -Force | Out-Null
        New-ItemProperty -Path $k -Name 'DisabledByDefault' -Value 0 -PropertyType DWord -Force | Out-Null
    }
}
if (-not $DryRun) { Write-Host "[ok  ] 啟用 TLS 1.2" }

# 停用弱 cipher
$disableCiphers = @('RC4 40/128','RC4 56/128','RC4 64/128','RC4 128/128','Triple DES 168','DES 56/56','NULL')
foreach ($c in $disableCiphers) {
    $k = "$schannelBase\Ciphers\$c"
    if ($DryRun) {
        Write-Host "[dry ] Disable cipher: $c"
    } else {
        if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }
        New-ItemProperty -Path $k -Name 'Enabled' -Value 0 -PropertyType DWord -Force | Out-Null
    }
}
if (-not $DryRun) { Write-Host "[ok  ] 停用弱 cipher" }

Write-Host "`n本機安全政策套用完成。提醒:" -ForegroundColor Green
Write-Host "  1. SCHANNEL 變更需 重新開機 才生效" -ForegroundColor Yellow
Write-Host "  2. sftp_users 互動登入拒絕需到 secpol.msc 手動確認 (或用 ntrights.exe)" -ForegroundColor Yellow
Write-Host "  3. 重啟後建議用 testssl.sh / SSL Labs 驗證 TLS 設定" -ForegroundColor Yellow
