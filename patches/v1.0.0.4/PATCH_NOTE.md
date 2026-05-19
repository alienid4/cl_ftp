# Patch v1.0.0.4 — OpenSSH 內網離線安裝 helper (用 Windows ISO sxs)

| 項目 | 內容 |
|---|---|
| **Patch 編號** | v1.0.0.4 |
| **發布日期** | 2026-05-19 |
| **狀態** | 🟡 緩解 (FoD source 不放 patch, 提供 ISO 取得 + 安裝 helper) |
| **相關 issue** | #010 (OpenSSH 0x800f0907) |
| **前置 patch** | v1.0.0.3 (install_offline.ps1 容錯, 已記錄 OpenSSH 失敗) |

---

## 問題回顧

跑 `install_offline.ps1` 在 Step 7 OpenSSH 失敗:
```
Add-WindowsCapability : Add-WindowsCapabilityCommand 0x800f0907
```

= **Windows 找不到 OpenSSH 的 FoD source**。內網無 Windows Update / WSUS FoD 時必出此錯。

v1.0.0.3 修正了「失敗不會 abort 整個 script」, 但 **OpenSSH 仍然沒裝**。本 patch 解決「**怎麼讓 OpenSSH 在內網裝起來**」。

---

## 為什麼 FoD source 不放 patch / GitHub

| 考量 | 說明 |
|---|---|
| 整套 sxs 大小 | **1-2 GB**, 超 GitHub 單檔 100 MB |
| 單 OpenSSH CAB | 5-10 MB, 可放但... |
| 版本依賴 | Server 2022 / 2019 / Win10 / Win11 CAB 不互通 |
| Microsoft 已公開 | Windows ISO 公開可下載, 沒理由 mirror |
| 資安考量 | 單 CAB 缺整體簽名鏈, 用 ISO mount 較完整 |

**結論**: FoD 太大、版本依賴強, 由 IT 提供 ISO 比較對。Patch 只放 helper 腳本。

---

## 解法 (4 條路, 擇一)

### 路徑 A: Windows Server 2022 ISO + sxs (推薦)

1. 跟公司 IT 索取 Windows Server 2022 ISO (跟 SF 主機相同版本)
2. ISO 拷到 SF 主機 (USB, 約 5 GB)
3. 跑本 patch 的 helper:
   ```powershell
   .\scripts\install_openssh_offline.ps1 -IsoPath 'D:\install\WindowsServer2022.iso'
   ```
4. 腳本會: Mount ISO → 找 sxs → 帶 `-Source` + `-LimitAccess` 安裝 → 驗證 → Dismount

### 路徑 B: 已 mount 或拷出 sxs 目錄

```powershell
.\scripts\install_openssh_offline.ps1 -SxsPath 'D:\sxs'
```

### 路徑 C: 從另一台已裝好的 Win Server 拷 OpenSSH binary

```powershell
# 在已裝 OpenSSH 的主機 (Server X):
Copy-Item 'C:\Program Files\OpenSSH' \\<SF>\C$\Program Files\OpenSSH -Recurse
Copy-Item 'C:\ProgramData\ssh' \\<SF>\C$\ProgramData\ssh -Recurse

# 在 SF 主機:
& "C:\Program Files\OpenSSH\install-sshd.ps1"
Set-Service sshd -StartupType Automatic
Start-Service sshd
```

⚠️ 此法 Windows Update 不會認 OpenSSH 為「已安裝」, 將來 patch 麻煩。建議**先做這個應急, 之後拿到 ISO 重裝**。

### 路徑 D: 公司 WSUS 加入 FoD package

跟系管申請: 「請把 OpenSSH FoD 加進 WSUS」。設好後 `Add-WindowsCapability` 自動成功。
**時程**: 1-3 週 (要 IT 變動 WSUS, 排程慢)。

---

## 取得 Windows Server 2022 ISO 的 3 個來源

| 來源 | 時程 | 限制 |
|---|---|---|
| **公司 IT VL 授權** (推薦) | 1-2 天 | 要走申請流程 |
| **Microsoft Evaluation Center** | 立即 | 180-day 評估版, 期限到要重灌 (或升級 VL 序號) |
| **MSDN/Visual Studio Subscription** | 立即 | 要有訂閱 |

Microsoft 公開下載連結:
- https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2022

評估版裝完 OpenSSH 沒問題, 即使 SF 主機是 VL 授權, 用 evaluation ISO 的 sxs 也可以裝 (FoD 來源不影響主系統授權)。

---

## 影響檔案

| 檔案 | 動作 |
|---|---|
| `scripts/install_openssh_offline.ps1` | **新增** |

`install_offline.ps1` 不需要改 (v1.0.0.3 已正確處理 OpenSSH 失敗)。

---

## 套用方式

### 方法 A: apply.ps1

```powershell
cd <SF-PROJECT-ROOT>
.\patches\v1.0.0.4\apply.ps1
```

### 方法 B: 手動拷貝

```powershell
Copy-Item patches\v1.0.0.4\files\scripts\install_openssh_offline.ps1 `
    scripts\install_openssh_offline.ps1 -Force
```

---

## 驗證

```powershell
# 1. 確認 helper 腳本存在
Get-Item .\scripts\install_openssh_offline.ps1

# 2. 試 dry-run (確認語法 OK)
.\scripts\install_openssh_offline.ps1 -IsoPath 'D:\install\xxx.iso' -DryRun

# 3. 拿到 ISO 後實際裝
.\scripts\install_openssh_offline.ps1 -IsoPath 'D:\install\WindowsServer2022.iso'

# 4. 確認 sshd 服務跑起來
Get-Service sshd | Format-Table Name, Status, StartType

# 5. 重跑 install_offline.ps1, OpenSSH step 應該變 [skip] 已安裝
cd deploy\offline
.\install_offline.ps1
```

---

## 相關連結

- 對應 issue: [issues_log #010](../../docs/dev-log/issues_log.md)
- 前一個 patch: [v1.0.0.3](../v1.0.0.3/) (idempotent + try-catch)
- Microsoft FoD 文件: https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse
