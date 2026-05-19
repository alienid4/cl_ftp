# Patch v1.0.0.5 — OpenSSH Portable 一鍵安裝 (PowerShell Team Win32-OpenSSH)

| 項目 | 內容 |
|---|---|
| **Patch 編號** | v1.0.0.5 |
| **發布日期** | 2026-05-19 |
| **狀態** | ✅ 完整解 (繞過 Windows FoD, 5 MB zip 解決 OpenSSH 內網安裝) |
| **相關 issue** | #010 (OpenSSH 0x800f0907 / FoD source 不全) |
| **前置 patch** | v1.0.0.4 (ISO sxs 路線, 但需 ISO + 完整 sxs) |

---

## 為什麼還要 v1.0.0.5 (v1.0.0.4 已經有 helper 了)

實際使用者場景:
- IT 給的 sxs 目錄**沒包 OpenSSH CAB** (只給 IE + NetFx3)
- Windows ISO 5 GB, USB 拷貝慢
- ISO 版本要跟主機完全一致, 容易拿錯
- 申請 ISO 走流程 1-2 天

**Win32-OpenSSH portable** 完全繞過這些痛點:
- 5 MB zip (vs 5 GB ISO)
- 不依賴 Windows Update / WSUS / FoD CAB
- 跟 FoD 版本同源 (PowerShell Team 官方)
- 所有 Windows 版本通用 (Server 2016+, Win10/11)

---

## 解法概要

```
[外網 PC]                                  [SF 主機 (內網)]

抓 OpenSSH-Win64.zip                       D:\OpenSSH-Win64.zip
(5 MB, GitHub)         ──USB── ►          ↓
                                            .\scripts\install_openssh_portable.ps1
                                              -ZipPath 'D:\OpenSSH-Win64.zip'
                                            ↓
                                            自動: 解壓 → 註冊 service → 啟動 → 防火牆
                                            ↓
                                            sshd 跑起來, 完成
```

---

## 步驟詳解

### Step 1: 外網下載 zip

連到 https://github.com/PowerShell/Win32-OpenSSH/releases/latest

下載 **`OpenSSH-Win64.zip`** (約 5 MB)

> 為什麼選 Win32-OpenSSH:
> - PowerShell Team (Microsoft 官方) 維護
> - 跟 Windows FoD `Add-WindowsCapability OpenSSH.Server` 同一份 codebase
> - GitHub 公開 release, 不需要 Microsoft 帳號

### Step 2: USB 拷到 SF 主機

放在任意路徑, 例: `D:\OpenSSH-Win64.zip`

### Step 3: 套用本 patch

```powershell
cd <SF-PROJECT-ROOT>
.\patches\v1.0.0.5\apply.ps1
```

→ 把 `install_openssh_portable.ps1` 拷到 `scripts/`

### Step 4: 跑 portable installer

```powershell
.\scripts\install_openssh_portable.ps1 -ZipPath 'D:\OpenSSH-Win64.zip'
```

腳本會做 6 步:
1. 系統管理員權限檢查
2. 已裝偵測 (idempotent, 已裝就 skip)
3. 驗證 zip + 解壓到 `C:\Program Files\OpenSSH\`
4. 跑官方 `install-sshd.ps1` 註冊 service
5. `Set-Service sshd -StartupType Automatic` + `Start-Service`
6. 新建防火牆 rule (TCP 22 入站)

預演模式: 加 `-DryRun`。

### Step 5: 驗證

```powershell
Get-Service sshd, ssh-agent | Format-Table Name, Status, StartType
Test-NetConnection -ComputerName localhost -Port 22
```

預期:
- sshd Running / Automatic
- ssh-agent Stopped / Automatic (可選啟動)
- TCP 22 Succeeded

---

## 影響檔案

| 檔案 | 動作 |
|---|---|
| `scripts/install_openssh_portable.ps1` | **新增** |

`install_offline.ps1` 不需要改 (v1.0.0.3 已正確處理 OpenSSH 失敗, 重跑會看到 OpenSSH 已裝 → skip)。

---

## 套用方式

### 方法 A: apply.ps1

```powershell
cd <SF-PROJECT-ROOT>
.\patches\v1.0.0.5\apply.ps1
```

### 方法 B: 手動拷貝

```powershell
Copy-Item patches\v1.0.0.5\files\scripts\install_openssh_portable.ps1 `
    scripts\install_openssh_portable.ps1 -Force
```

---

## Portable vs FoD 比較

| 比較項 | FoD (Patch v1.0.0.4) | Portable (Patch v1.0.0.5) |
|---|---|---|
| 檔案大小 | 5 GB ISO 或 10 MB CAB | **5 MB zip** |
| 取得管道 | Microsoft (ISO/WSUS/Eval Center) | **GitHub Release** (公開) |
| 版本依賴 | Server 2019 ≠ 2022 ≠ Win10 | **全 Windows 通用** |
| 內網申請 | 等 IT 給 ISO (1-2 天) | **立即 (USB 拷貝)** |
| Windows Update 認 | ✅ Capability: Installed | ❌ Capability: NotPresent |
| sshd 行為 | 完全一樣 | **完全一樣** |
| sshd_config 位置 | `C:\ProgramData\ssh` | **相同** |
| 將來更新 | Windows Update / 手動 | 抓新 zip 覆蓋 |
| 適用場景 | 公司 WSUS 完整 | **內網無 FoD source** ← 你的情境 |

**結論**: 內網主機強烈推薦 portable, 不犧牲功能, 省 99% 麻煩。

---

## 升級 OpenSSH (將來)

PowerShell Team 新版出來時:

```powershell
# 1. 外網抓新 zip
# 2. USB 拷到 SF 主機
# 3. 停 service
Stop-Service sshd, ssh-agent

# 4. 備份舊版
Rename-Item 'C:\Program Files\OpenSSH' 'C:\Program Files\OpenSSH.old'

# 5. 解壓新版
Expand-Archive 'D:\OpenSSH-Win64-new.zip' -DestinationPath 'C:\Program Files\' -Force
Rename-Item 'C:\Program Files\OpenSSH-Win64' 'OpenSSH'

# 6. 啟動
Start-Service sshd

# 7. 沒問題刪舊版
Remove-Item 'C:\Program Files\OpenSSH.old' -Recurse -Force
```

---

## 驗證

```powershell
# 1. 確認 helper 腳本存在
Get-Item .\scripts\install_openssh_portable.ps1

# 2. Dry-run 預演
.\scripts\install_openssh_portable.ps1 -ZipPath 'D:\OpenSSH-Win64.zip' -DryRun

# 3. 實際裝
.\scripts\install_openssh_portable.ps1 -ZipPath 'D:\OpenSSH-Win64.zip'

# 4. 確認 service
Get-Service sshd | Format-Table Name, Status, StartType

# 5. 確認 port
Test-NetConnection -ComputerName localhost -Port 22

# 6. 從別台 ssh 測 (在另一台主機)
ssh administrator@<SF-IP>

# 7. 重跑 install_offline.ps1, OpenSSH step 應該變 [skip]
cd deploy\offline
.\install_offline.ps1
```

---

## 故障排除

### Q1: 解壓後 install-sshd.ps1 提示 "Set-ExecutionPolicy"

```powershell
# 暫時放寬
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
& 'C:\Program Files\OpenSSH\install-sshd.ps1'
```

### Q2: sshd 啟動失敗

```powershell
# 看詳細 log
Get-EventLog -LogName Application -Source OpenSSH -Newest 20

# 常見原因: host key 沒生成
& 'C:\Program Files\OpenSSH\ssh-keygen.exe' -A
```

### Q3: 防火牆 rule 已存在但 disabled

腳本會自動 enable, 不用手動。

### Q4: 22 port 已被佔用

```powershell
Get-NetTCPConnection -LocalPort 22
# 找到佔用 process, 停掉或改 sshd port
```

---

## 相關連結

- 對應 issue: [issues_log #010](../../docs/dev-log/issues_log.md)
- Win32-OpenSSH 官方: https://github.com/PowerShell/Win32-OpenSSH
- 對比 patch: [v1.0.0.4](../v1.0.0.4/) (ISO sxs 路線, 備案)
- 微軟文件: https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse
