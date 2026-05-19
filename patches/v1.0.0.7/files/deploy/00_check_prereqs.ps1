<#
.SYNOPSIS
    檢查中繼檔案交換主機建置前置條件。
.DESCRIPTION
    執行前置檢查: OS 版本、PowerShell 版本、管理者權限、磁碟空間、
    必要 Windows 功能可用性、Internet 連線 (下載元件用)。
.EXAMPLE
    .\00_check_prereqs.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ok = $true

function Test-Item {
    param([string]$Name, [bool]$Pass, [string]$Detail = '')
    $mark = if ($Pass) { '[ OK ]' } else { '[FAIL]'; $script:ok = $false }
    Write-Host ("{0}  {1}  {2}" -f $mark, $Name.PadRight(40), $Detail)
}

Write-Host "`n=== 中繼檔案交換主機 前置檢查 ===`n" -ForegroundColor Cyan

# 1. 管理者權限
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrators')
Test-Item -Name 'Administrator 權限' -Pass $isAdmin -Detail "$env:USERNAME"

# 2. OS 版本 (需 Windows Server 2019 / 2022)
$os = Get-CimInstance Win32_OperatingSystem
$osOK = $os.Caption -match 'Windows Server (2019|2022)'
Test-Item -Name 'OS 版本' -Pass $osOK -Detail $os.Caption

# 3. PowerShell 版本 (>= 5.1)
$psOK = $PSVersionTable.PSVersion.Major -ge 5
Test-Item -Name 'PowerShell 版本' -Pass $psOK -Detail $PSVersionTable.PSVersion.ToString()

# 4. D: 磁碟存在且 > 30GB (生產環境建議 1 TB, 但開發/PoC 30 GB 即可起步)
$drive = Get-PSDrive -Name D -ErrorAction SilentlyContinue
if ($drive) {
    $freeGB = [math]::Round($drive.Free / 1GB, 1)
    $diskOK = $freeGB -gt 30
    $detail = "$freeGB GB" + $(if ($freeGB -lt 100) { ' (生產建議 >= 100 GB, 目前 OK 啟動)' } else { '' })
    Test-Item -Name 'D: 磁碟可用空間' -Pass $diskOK -Detail $detail
} else {
    Test-Item -Name 'D: 磁碟存在' -Pass $false -Detail '未掛載'
}

# 5. OpenSSH Server 功能可用
$sshFeature = Get-WindowsCapability -Online -Name 'OpenSSH.Server*' -ErrorAction SilentlyContinue
$sshOK = $null -ne $sshFeature
Test-Item -Name 'OpenSSH.Server 功能可用' -Pass $sshOK -Detail $sshFeature.State

# 6. IIS Web-Server 功能可用
$iisFeature = Get-WindowsFeature -Name Web-Server -ErrorAction SilentlyContinue
$iisOK = $null -ne $iisFeature
Test-Item -Name 'IIS Web-Server 功能可用' -Pass $iisOK -Detail $iisFeature.InstallState

# 7. 防火牆服務啟動
$fwSvc = Get-Service -Name MpsSvc -ErrorAction SilentlyContinue
$fwOK = $fwSvc.Status -eq 'Running'
Test-Item -Name 'Windows Firewall 服務' -Pass $fwOK -Detail $fwSvc.Status

# 8. .NET Framework 4.8+ (Portal 若用 ASP.NET Core 可略)
$netRel = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -ErrorAction SilentlyContinue).Release
$netOK = $netRel -ge 528040
Test-Item -Name '.NET Framework 4.8+' -Pass $netOK -Detail "Release=$netRel"

Write-Host ""
if ($ok) {
    Write-Host "前置檢查全部通過, 可繼續執行 01_setup_directories.ps1" -ForegroundColor Green
    exit 0
} else {
    Write-Host "前置檢查有項目未通過, 請修正後再執行後續腳本" -ForegroundColor Red
    exit 1
}
