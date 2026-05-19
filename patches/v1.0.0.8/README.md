# SF Patch v1.0.0.8 — 快速使用

> 修 sshd 啟動失敗 ('OpenSSH SSH Server (sshd)' 無法啟動)。**必裝**。

## 一鍵套用

```
雙擊 run_patch.cmd
```

或 PowerShell:
```powershell
.\install_patch.ps1
```

## 套用後

```powershell
cd C:\Users\xxx\Desktop\sf_offline_bundle_20260519_0901\deploy
.\03_install_openssh.ps1
# 預期: [ok] sshd 重啟 (不再 fail)

Get-Service sshd
# 預期: Running / Automatic
```

## 修了什麼

| 問題 | 修法 |
|---|---|
| `Subsystem sftp sftp-server.exe` 在 portable OpenSSH 找不到 | 改 `internal-sftp` (sshd 內建) |
| `Banner C:/ProgramData/ssh/banner.txt` 檔案不存在 sshd 不啟動 | 03_install_openssh.ps1 自動建 banner.txt |

詳見 [PATCH_NOTE.md](PATCH_NOTE.md)。
