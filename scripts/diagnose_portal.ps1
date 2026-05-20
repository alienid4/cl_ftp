<#
.SYNOPSIS
    Portal 訪問「空白」診斷 — 一行找出 5 種可能原因。
.DESCRIPTION
    對應 Linux 對照:
    - 對 service 跑沒 = systemctl status
    - 對 port 開沒  = ss -tlnp / lsof -i :5000
    - 對 HTTP 回應  = curl -v http://localhost:5000/
    - 對 log 錯誤   = journalctl -u app
#>
$ErrorActionPreference = 'Continue'

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  Portal 空白診斷" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

# === Check 1: Service 跑沒? ===
Write-Host ""
Write-Host "[1] Portal Service 狀態 (對應: systemctl status FileExchangePortal)" -ForegroundColor Yellow
$svc = Get-Service FileExchangePortal -ErrorAction SilentlyContinue
if ($svc) {
    Write-Host "    Name: $($svc.Name), Status: $($svc.Status), StartType: $($svc.StartType)"
    if ($svc.Status -ne 'Running') {
        Write-Host "    [問題 #1] Service 不在跑!" -ForegroundColor Red
        Write-Host "    修法: Start-Service FileExchangePortal" -ForegroundColor Yellow
    } else {
        Write-Host "    [ok] Service Running" -ForegroundColor Green
    }
} else {
    Write-Host "    [問題 #1] Service FileExchangePortal 不存在 — 還沒註冊" -ForegroundColor Red
    Write-Host "    修法: 1. 先抓 Python wheels  2. 跑 poc_setup_c_drive.ps1" -ForegroundColor Yellow
}

# === Check 2: 5000 Port 開沒? Listen 哪個介面? ===
Write-Host ""
Write-Host "[2] Port 5000 監聽狀態 (對應: ss -tlnp | grep 5000)" -ForegroundColor Yellow
$conn = Get-NetTCPConnection -State Listen -LocalPort 5000 -ErrorAction SilentlyContinue
if ($conn) {
    foreach ($c in $conn) {
        Write-Host "    LocalAddress: $($c.LocalAddress), Port: $($c.LocalPort), PID: $($c.OwningProcess)"
        if ($c.LocalAddress -eq '127.0.0.1') {
            Write-Host "    [問題 #2] 只 listen localhost (127.0.0.1) — 別台主機連不到!" -ForegroundColor Red
            Write-Host "    修法: 改 C:\_portal\app\wsgi.py 把 host='127.0.0.1' 改成 host='0.0.0.0'" -ForegroundColor Yellow
            Write-Host "          然後 Restart-Service FileExchangePortal" -ForegroundColor Yellow
        } elseif ($c.LocalAddress -in @('0.0.0.0', '::', '*')) {
            Write-Host "    [ok] Listen 全介面" -ForegroundColor Green
        }
    }
    # 看哪個 process 在聽
    $pid = $conn[0].OwningProcess
    $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
    if ($proc) {
        Write-Host "    Process: $($proc.ProcessName) (PID=$pid)"
    }
} else {
    Write-Host "    [問題 #2] 5000 port 完全沒在 listen — Portal 沒起來" -ForegroundColor Red
    Write-Host "    修法: 看 Check 1 的 service, 或抓 wheels 重部署" -ForegroundColor Yellow
}

# === Check 3: 從 localhost HTTP 訪問 ===
Write-Host ""
Write-Host "[3] HTTP 訪問測試 (對應: curl -v http://localhost:5000/)" -ForegroundColor Yellow
try {
    $resp = Invoke-WebRequest 'http://localhost:5000/' -UseBasicParsing -MaximumRedirection 0 -TimeoutSec 5 -ErrorAction Stop
    Write-Host "    HTTP $($resp.StatusCode) — body length: $($resp.RawContentLength) bytes"
    if ($resp.RawContentLength -eq 0) {
        Write-Host "    [問題 #3] 回應 body 為空" -ForegroundColor Red
    } else {
        $preview = $resp.Content.Substring(0, [Math]::Min(200, $resp.Content.Length))
        Write-Host "    [ok] 有 body, 前 200 字: $preview" -ForegroundColor Green
    }
} catch [System.Net.WebException] {
    $statusCode = [int]$_.Exception.Response.StatusCode
    Write-Host "    HTTP $statusCode (這代表 server 回應了, 不算空白)"
    if ($statusCode -eq 302) {
        $loc = $_.Exception.Response.Headers['Location']
        Write-Host "    [info] 302 Redirect → $loc" -ForegroundColor Cyan
        Write-Host "    [問題 #3] / 路由 @login_required, 需要登入" -ForegroundColor Yellow
        Write-Host "    在瀏覽器訪問就會自動 redirect 到 login 頁, 不算空白" -ForegroundColor Yellow
        Write-Host "    請直接訪問: http://<SF-IP>:5000/auth/login" -ForegroundColor Cyan
    } elseif ($statusCode -eq 500) {
        Write-Host "    [問題 #3] HTTP 500 — Flask 內部錯誤" -ForegroundColor Red
        Write-Host "    看下面 Check 5 的 log" -ForegroundColor Yellow
    } else {
        Write-Host "    [問題 #3] 非預期 HTTP $statusCode" -ForegroundColor Red
    }
} catch {
    Write-Host "    [FAIL] 連不到: $($_.Exception.Message)" -ForegroundColor Red
}

# === Check 4: Python wheels / venv 在嗎? ===
Write-Host ""
Write-Host "[4] Portal Python 環境檢查" -ForegroundColor Yellow
$venv = 'C:\_portal\app\.venv'
$waitress = "$venv\Scripts\waitress-serve.exe"
if (Test-Path $venv) {
    Write-Host "    [ok] venv: $venv" -ForegroundColor Green
    if (Test-Path $waitress) {
        Write-Host "    [ok] waitress-serve.exe 存在" -ForegroundColor Green
    } else {
        Write-Host "    [問題 #4] waitress-serve.exe 不存在 — pip install 沒成功" -ForegroundColor Red
        Write-Host "    修法: cd C:\_portal\app; .\.venv\Scripts\pip install --no-index --find-links C:\install\python_wheels -r requirements.txt" -ForegroundColor Yellow
    }
    # 列出已安裝套件
    $pip = "$venv\Scripts\pip.exe"
    if (Test-Path $pip) {
        $installed = & $pip list 2>&1 | Select-Object -First 15
        Write-Host "    已裝套件 (前 15):" -ForegroundColor DarkGray
        $installed | ForEach-Object { Write-Host "      $_" -ForegroundColor DarkGray }
    }
} else {
    Write-Host "    [問題 #4] venv 不存在: $venv" -ForegroundColor Red
    Write-Host "    Portal 還沒部署. 修法: 跑 poc_setup_c_drive.ps1" -ForegroundColor Yellow
}

# === Check 5: Portal log ===
Write-Host ""
Write-Host "[5] Portal log (對應: journalctl -u FileExchangePortal -n 20)" -ForegroundColor Yellow
$logCandidates = @(
    'C:\_portal\logs\portal.log',
    'C:\_portal\logs\portal-stdout.log',
    'C:\_portal\logs\portal-stderr.log'
)
$foundLog = $false
foreach ($l in $logCandidates) {
    if (Test-Path $l) {
        Write-Host "    Log: $l (最後 10 行)" -ForegroundColor Cyan
        Get-Content $l -Tail 10
        $foundLog = $true
    }
}
if (-not $foundLog) {
    Write-Host "    沒找到 portal log 檔" -ForegroundColor DarkGray
    Write-Host "    試 Event Log:" -ForegroundColor Cyan
    Get-WinEvent -LogName Application -MaxEvents 20 -ErrorAction SilentlyContinue |
        Where-Object { $_.Message -like '*Portal*' -or $_.Message -like '*Flask*' -or $_.Message -like '*waitress*' } |
        Select-Object -First 5 |
        Format-Table TimeCreated, LevelDisplayName, Message -Wrap
}

# === 結論 ===
Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  建議下一步" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
$ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike '169.*' -and $_.IPAddress -ne '127.0.0.1' } | Select-Object -First 1).IPAddress

if (-not $svc -or $svc.Status -ne 'Running') {
    Write-Host "1. 沒 service, 抓 wheels 重部署 (見 Check 1 / 4)" -ForegroundColor Yellow
} elseif (-not $conn) {
    Write-Host "1. service 跑但沒 listen, 看 NSSM 設定 (Check 4)" -ForegroundColor Yellow
} elseif ($conn -and $conn[0].LocalAddress -eq '127.0.0.1') {
    Write-Host "1. 改 wsgi.py 把 host=127.0.0.1 改 0.0.0.0:" -ForegroundColor Cyan
    Write-Host "   `$wsgi = 'C:\_portal\app\wsgi.py'"
    Write-Host "   (Get-Content `$wsgi) -replace `"host='127.0.0.1'`", `"host='0.0.0.0'`" | Set-Content `$wsgi"
    Write-Host "   Restart-Service FileExchangePortal"
} else {
    Write-Host "1. 直接訪問 login 頁:" -ForegroundColor Cyan
    Write-Host "   http://$ip`:5000/auth/login" -ForegroundColor Green
    Write-Host "2. 如果還是空白, 看 Check 3 的 HTTP status code"
}
Write-Host ""
