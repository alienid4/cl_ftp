<#
.SYNOPSIS
    [內網 SF 主機] 用 Windows ISO 的 sxs source 安裝 OpenSSH Server, 不需 Internet。
.DESCRIPTION
    解決 install_offline.ps1 Step 7 OpenSSH 失敗 (0x800f0907, 內網無 FoD source)。

    用法:
    1. 準備 Windows Server 2022 ISO (跟 SF 主機相同版本)
    2. 拷到 SF 主機 (USB)
    3. 跑這支, 自動 mount ISO + 帶 -Source 安裝

    idempotent: 已裝就 skip, 重跑無害。
.PARAMETER IsoPath
    Windows Server 2022 ISO 完整路徑, 例: 'D:\install\WindowsServer2022.iso'
.PARAMETER SxsPath
    如果您已 mount ISO 或有 sxs 目錄, 直接指定路徑跳過 mount, 例: 'D:\sxs'
.PARAMETER DryRun
    只列出將執行的動作。
.EXAMPLE
    # 自動 mount ISO
    .\install_openssh_offline.ps1 -IsoPath 'D:\install\WindowsServer2022.iso'
.EXAMPLE
    # 已 mount 過或拷 sxs 出來
    .\install_openssh_offline.ps1 -SxsPath 'D:\sxs'
#>
[CmdletBinding(DefaultParameterSetName='Iso')]
param(
    [Parameter(ParameterSetName='Iso')]
    [string]$IsoPath,

    [Parameter(ParameterSetName='Sxs')]
    [string]$SxsPath,

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

Write-Host "`n=== OpenSSH Offline Installer (用 ISO sxs source) ===" -ForegroundColor Cyan

# ===== Step 1: 已裝偵測 =====
$sshCap = Get-WindowsCapability -Online -Name 'OpenSSH.Server*' -ErrorAction SilentlyContinue
if (-not $sshCap) {
    Write-Host "[FAIL] 系統不支援 OpenSSH capability (Windows 版本太舊?)" -ForegroundColor Red
    exit 1
}

Write-Host "[info] capability: $($sshCap.Name)"
Write-Host "[info] 當前狀態: $($sshCap.State)"

if ($sshCap.State -eq 'Installed') {
    Write-Host "[skip] OpenSSH.Server 已安裝, 不需要再做" -ForegroundColor Green
    Write-Host ""
    Write-Host "確認 service:"
    Get-Service sshd, ssh-agent -ErrorAction SilentlyContinue | Format-Table Name, Status, StartType -AutoSize
    exit 0
}

# ===== Step 2: 決定 SxsPath =====
$mountedIso = $null
if ($PSCmdlet.ParameterSetName -eq 'Iso') {
    if (-not (Test-Path $IsoPath)) {
        Write-Host "[FAIL] ISO 不存在: $IsoPath" -ForegroundColor Red
        Write-Host ""
        Write-Host "需要 Windows Server 2022 ISO. 取得方式:" -ForegroundColor Yellow
        Write-Host "  1. 跟公司 IT 索取 (VL ISO)"
        Write-Host "  2. 從 Microsoft Evaluation Center 抓 180-day 評估版:"
        Write-Host "     https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2022"
        Write-Host "  3. 從別台已裝好的 Win Server 2022 主機拷 sxs 目錄出來"
        exit 1
    }

    Write-Host ""
    Write-Host "[exec] Mount-DiskImage $IsoPath"
    if ($DryRun) {
        Write-Host "[dry] (skip mount in dry-run)"
        $SxsPath = 'D:\dummy\sxs'  # placeholder
    } else {
        $mountedIso = Mount-DiskImage -ImagePath $IsoPath -PassThru
        $driveLetter = ($mountedIso | Get-Volume).DriveLetter
        if (-not $driveLetter) {
            Write-Host "[FAIL] Mount 失敗或找不到 drive letter" -ForegroundColor Red
            exit 1
        }
        $SxsPath = "${driveLetter}:\sources\sxs"
        Write-Host "[ok] ISO mount 到 ${driveLetter}:\"
        Write-Host "[ok] sxs 路徑: $SxsPath"
    }
}

# 驗證 sxs path
if (-not $DryRun) {
    if (-not (Test-Path $SxsPath)) {
        Write-Host "[FAIL] sxs 目錄不存在: $SxsPath" -ForegroundColor Red
        if ($mountedIso) {
            Dismount-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue
        }
        exit 1
    }

    # 看 sxs 內有沒有 OpenSSH CAB
    $opensshCab = Get-ChildItem $SxsPath -Filter '*OpenSSH-Server*.cab' -ErrorAction SilentlyContinue
    if ($opensshCab) {
        Write-Host "[ok] 找到 OpenSSH CAB: $($opensshCab.Name) ($('{0:N1}' -f ($opensshCab.Length/1MB)) MB)"
    } else {
        Write-Host "[warn] sxs 內找不到 *OpenSSH-Server*.cab" -ForegroundColor Yellow
        Write-Host "  可能是 ISO 版本不對, 或 sxs 路徑錯" -ForegroundColor Yellow
        Write-Host "  繼續嘗試 Add-WindowsCapability, Windows 自己找..."
    }
}

# ===== Step 3: Add-WindowsCapability =====
Write-Host ""
Write-Host "[exec] Add-WindowsCapability -Online -Name $($sshCap.Name) -Source $SxsPath -LimitAccess"
if ($DryRun) {
    Write-Host "[dry] (skip)"
} else {
    try {
        Add-WindowsCapability -Online -Name $sshCap.Name -Source $SxsPath -LimitAccess -ErrorAction Stop | Out-Null
        Write-Host "[ok] OpenSSH.Server 安裝完成" -ForegroundColor Green

        # 驗證
        Start-Sleep -Seconds 2
        $sshSvc = Get-Service sshd -ErrorAction SilentlyContinue
        if ($sshSvc) {
            Write-Host ""
            Write-Host "===== 驗證 =====" -ForegroundColor Cyan
            Write-Host "sshd service:"
            $sshSvc | Format-Table Name, Status, StartType -AutoSize
            Write-Host ""
            Write-Host "建議下一步:"
            Write-Host "  Set-Service sshd -StartupType Automatic"
            Write-Host "  Start-Service sshd"
            Write-Host "  Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' | Enable-NetFirewallRule"
            Write-Host ""
            Write-Host "或重跑 install_offline.ps1, 它會自動處理上述步驟" -ForegroundColor Cyan
        }
    } catch {
        Write-Host "[FAIL] $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ""
        Write-Host "可能原因:" -ForegroundColor Yellow
        Write-Host "  1. ISO 版本跟 SF 主機 Windows 不符 (例如 ISO 是 2019 但主機是 2022)"
        Write-Host "  2. sxs 路徑不對, 試試 mount 點根目錄"
        Write-Host "  3. ISO 不完整 (重新下載)"
    } finally {
        # 一律 dismount
        if ($mountedIso) {
            Write-Host ""
            Write-Host "[exec] Dismount-DiskImage"
            Dismount-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue
            Write-Host "[ok] ISO 已 dismount"
        }
    }
}
