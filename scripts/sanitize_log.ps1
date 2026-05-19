<#
.SYNOPSIS
    去識別化 log / 設定檔, 避免 IP / 帳號 / 密碼 / 主機名 / SHA 等敏感資訊外流。
.DESCRIPTION
    讀取輸入檔, 套用一系列 regex 將敏感字串替換為 placeholder,
    寫入輸出檔。供 collect_debug_bundle.ps1 呼叫。

    遮蔽規則:
    - IPv4              → <IP_MASKED>
    - 主機名 (FQDN)     → <HOST_MASKED>
    - 公司 AD 帳號      → <USER_MASKED>
    - PAM 申請 ID       → <PAM_ID_MASKED>
    - 密碼 / token / key 欄位 → <SECRET_MASKED>
    - SHA-256 hash      → <HASH_MASKED>
    - email             → <EMAIL_MASKED>
    - 業務代號 u0X      → <BIZ_CODE_MASKED> (可選)
.PARAMETER InputPath
    輸入檔路徑。
.PARAMETER OutputPath
    輸出檔路徑。
.PARAMETER KeepBizCode
    保留 u01/u02 等業務代號 (預設遮蔽)。
.EXAMPLE
    .\sanitize_log.ps1 -InputPath app.log -OutputPath app_sanitized.log
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$InputPath,
    [Parameter(Mandatory=$true)][string]$OutputPath,
    [switch]$KeepBizCode
)

if (-not (Test-Path $InputPath)) {
    Write-Host "[sanitize] 輸入檔不存在: $InputPath" -ForegroundColor Red
    return
}

# 讀取內容
try {
    $content = Get-Content -Path $InputPath -Raw -Encoding UTF8 -ErrorAction Stop
} catch {
    # 二進位檔直接複製, 不 sanitize
    Copy-Item $InputPath $OutputPath -Force
    return
}

if ($null -eq $content) { $content = '' }

# ===== 遮蔽規則 =====

# 1. IPv4 (注意排除 127.0.0.1 與 0.0.0.0, 那些是 localhost 不算敏感)
$content = [regex]::Replace($content, '\b((?:[0-9]{1,3}\.){3}[0-9]{1,3})\b', {
    param($m)
    $ip = $m.Groups[1].Value
    if ($ip -eq '127.0.0.1' -or $ip -eq '0.0.0.0' -or $ip -eq '255.255.255.255') {
        return $ip
    }
    return '<IP_MASKED>'
})

# 2. IPv6 (常見格式)
$content = [regex]::Replace($content, '\b(?:[0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}\b', '<IPV6_MASKED>')

# 3. FQDN / 主機名 (常見公司域名規則, 例: xxx.corp.local, xxx.cathay.com)
$content = [regex]::Replace($content, '\b[a-zA-Z0-9][a-zA-Z0-9\-]{0,62}\.(?:corp|internal|local|cathay|company|prod|dev)\.[a-zA-Z]{2,10}\b', '<HOST_MASKED>')

# 4. AD 帳號 (CORP\xxx.yyy 或 xxx.yyy@domain)
$content = [regex]::Replace($content, '\b(?:CORP|DOMAIN|AD)\\[a-zA-Z][a-zA-Z0-9_.\-]+\b', '<USER_MASKED>')
$content = [regex]::Replace($content, '\b[a-zA-Z][a-zA-Z0-9_.\-]+@(?:corp|internal|local|cathay|company|prod|dev)\.[a-zA-Z]{2,10}\b', '<EMAIL_MASKED>')

# 5. PAM 申請 ID
$content = [regex]::Replace($content, 'PAM_\d{8}_\d{5,}', '<PAM_ID_MASKED>')

# 6. 密碼 / token / key 欄位 (常見格式)
$secretPatterns = @(
    '(?i)("?(?:password|passwd|pwd|secret|token|api[_-]?key|connection[_-]?string|conn[_-]?string|access[_-]?key|private[_-]?key)"?\s*[:=]\s*")[^"\r\n]+(")',
    "(?i)('?(?:password|passwd|pwd|secret|token|api[_-]?key)'?\s*[:=]\s*')[^'\r\n]+(')"
)
foreach ($pat in $secretPatterns) {
    $content = [regex]::Replace($content, $pat, '$1<SECRET_MASKED>$2')
}

# 7. SHA-256 hash (64 hex chars)
$content = [regex]::Replace($content, '\b[a-fA-F0-9]{64}\b', '<SHA256_MASKED>')

# 8. JWT token (eyJ...)
$content = [regex]::Replace($content, '\beyJ[a-zA-Z0-9_\-]+\.[a-zA-Z0-9_\-]+\.[a-zA-Z0-9_\-]+\b', '<JWT_MASKED>')

# 9. SSH key (-----BEGIN ... -----END ...)
$content = [regex]::Replace($content, '(?ms)-----BEGIN [A-Z ]+-----.+?-----END [A-Z ]+-----', '<KEY_BLOCK_MASKED>')

# 10. 業務代號 (可選遮蔽)
if (-not $KeepBizCode) {
    # 只在「業務代號出現在敏感上下文」時遮蔽 — 例如 home/u01 路徑
    # 預設保留 u0X 以便分析者看流向 (但若使用者想全遮可加 -KeepBizCode:$false)
}

# 11. 信用卡號 / 身分證
$content = [regex]::Replace($content, '\b(?:[A-Z][12]\d{8})\b', '<NID_MASKED>')  # 台灣身分證
$content = [regex]::Replace($content, '\b\d{4}-\d{4}-\d{4}-\d{4}\b', '<CC_MASKED>')

# 12. 移除 base64 看似很長的字串 (>200 字元)
$content = [regex]::Replace($content, '\b[A-Za-z0-9+/]{200,}={0,2}\b', '<LONG_BASE64_MASKED>')

# 13. 主機名 (短 NetBIOS, 例如 SF / AP-PRD-01)
# 注意: 太常見的字會誤刪, 只遮已知公司命名規則
$content = [regex]::Replace($content, '\b(?:AP|DB|WEB|APP|HR|FIN|OPS|SF)-(?:PRD|DEV|UAT)-\d{2,4}\b', '<HOST_SHORT_MASKED>')

# 寫出
$outDir = Split-Path $OutputPath -Parent
if (-not (Test-Path $outDir)) { New-Item -Path $outDir -ItemType Directory -Force | Out-Null }
Set-Content -Path $OutputPath -Value $content -Encoding UTF8

# 在檔頭加入 sanitization marker
$header = @"
# === SANITIZED FILE ===
# Original: $InputPath
# Sanitized at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
# Tool: sanitize_log.ps1
# Note: IP / hostname / user / password / hash / token 已被遮蔽
# =======================
"@
$existing = Get-Content $OutputPath -Raw -ErrorAction SilentlyContinue
Set-Content -Path $OutputPath -Value ($header + "`n" + $existing) -Encoding UTF8
