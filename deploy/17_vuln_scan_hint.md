# 弱點掃描整合指引

對齊主管圖「安全防護 → 弱點掃描」要求。SF 主機本身不執行掃描, 而是配合公司既有弱掃工具或標準工具進行季度檢查。

---

## 推薦工具 (擇一或併用)

### 1. Microsoft Defender Vulnerability Management (Windows 內建, 0 元)

Windows 10/11/Server 2022 內建, 透過 Defender 介面即可使用。

```powershell
# 啟用 Defender Vulnerability Management (需 Defender for Endpoint 授權)
Set-MpPreference -EnableNetworkProtection Enabled

# 查看主機弱點
Get-MpThreatDetection
Get-MpThreat
```

### 2. Microsoft Baseline Security Analyzer (MBSA, 舊版但仍可用)

- 下載: https://www.microsoft.com/en-us/download/details.aspx?id=7558
- 適用 Windows Server 2019+
- 排程每月跑一次, 輸出 HTML 報告
- 檢查項目: Patch 缺漏 / IIS 設定弱點 / SQL 弱點 / 帳號政策

### 3. Nessus (商用, 公司可能已有授權)

- 由公司既有 Nessus Server 排程掃 SF 主機 IP
- SF 主機開放掃描來源 IP 經過防火牆白名單
- 建議: 每季 1 次完整掃, 每月 1 次認證掃 (authenticated scan)

```
Nessus 掃描設定:
- Target: <SF 主機 IP>
- Scan type: Advanced Network Scan
- 認證: 使用者 svc_vulnscan (給最小權限, 唯讀)
- Credentials: SMB + SSH (給 OpenSSH)
- Schedule: 每月 1 日 02:00
```

### 4. OpenVAS / Greenbone (開源)

- 免費替代 Nessus
- 適合預算受限環境
- 部署在公司內網一台 Linux VM
- 從該 VM 掃描 SF (IP 經防火牆白名單)

---

## SF 主機需要為掃描配合的設定

### 防火牆放行掃描來源 IP

```powershell
New-NetFirewallRule -Name 'FX-VulnScan-In' `
    -DisplayName 'FileExchange Vuln Scanner Inbound' `
    -Direction Inbound -Protocol TCP -LocalPort Any `
    -Action Allow -Enabled True `
    -RemoteAddress '<掃描工具 IP>' `
    -Profile Domain
```

### 建立掃描專用帳號 (最小權限)

```powershell
# 建立本機帳號 svc_vulnscan
$pwd = ConvertTo-SecureString '<安全密碼>' -AsPlainText -Force
New-LocalUser -Name 'svc_vulnscan' -Password $pwd `
    -Description 'Vulnerability scanner service account (read-only)' `
    -PasswordNeverExpires:$false

# 加入 Performance Monitor Users 群組 (讓掃描工具能讀效能資料)
Add-LocalGroupMember -Group 'Performance Monitor Users' -Member 'svc_vulnscan'

# 拒絕互動式登入
# (透過 secpol.msc 設定 SeDenyInteractiveLogonRight)
```

---

## 排程建議

| 頻率 | 動作 | 工具 |
|---|---|---|
| 即時 | Defender 即時防護 | Windows Defender (已由 13_setup_defender.ps1 設定) |
| 每日 | Defender 快掃 D:\DataExchange | Defender (已設定) |
| 每週 | Defender 完整掃描 | Defender (已設定) |
| 每月 | MBSA / Defender Vulnerability 完整檢查 | MBSA / Defender |
| 每季 | Nessus / OpenVAS 完整掃描 | 公司既有平台 |
| 每年 | 第三方滲透測試 | 委外資安公司 |

---

## 弱掃結果處理流程

```
弱掃完成 → 產生報告
    │
    ▼
高風險 (Critical / High)
    │
    ▼
立即修補 (24-72 小時內), AuditLog 留紀錄
    │
    ▼
中風險 (Medium)
    │
    ▼
排入 Patch 管理流程, 月度更新
    │
    ▼
低風險 (Low / Info)
    │
    ▼
評估是否處理 (可能 false positive), 文件記載
```

---

## 驗證項目

- [ ] 公司既有掃描工具能掃 SF 主機
- [ ] Defender 介面看得到主機弱點清單
- [ ] 至少一次完整 Nessus / OpenVAS 掃描報告
- [ ] 高風險弱點 100% 修補 (或文件化例外)
- [ ] 修補後重掃驗證

---

## 注意事項

1. **不要在尖峰時段掃** — 認證掃描會用較多資源
2. **掃描帳號最小權限** — svc_vulnscan 只給必要讀取權, 絕不給 Admin
3. **掃描 log 也要留** — Defender / Nessus 自己有 log, 也可同步到 SF AuditLog (透過排程)
4. **OpenSSH / IIS / SQL 更新** — 一定要關注這三個套件的 CVE
