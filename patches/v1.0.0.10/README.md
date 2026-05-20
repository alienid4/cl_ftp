# SF Patch v1.0.0.10 — 快速使用

> sshd 仍啟動失敗 + 04 帳號可延後 + 09 wheels 離線安裝。**必裝**。

## 一鍵套用

```
雙擊 run_patch.cmd
```

## 套完之後

```powershell
cd <sf_bundle>\deploy

# 重啟 sshd (新 sshd_config 修了 DenyUsers SF\Administrator 問題)
.\03_install_openssh.ps1
Get-Service sshd

# 重跑 install_offline (04 自動 skip, 不卡密碼 prompt)
cd offline
.\install_offline.ps1
```

## 修了什麼

| 檔 | 改了什麼 |
|---|---|
| `config/sshd_config` | 拿掉 `SF\Administrator` (工作群組找不到), 註解 `Match User Administrator` |
| `04_create_sftp_accounts.ps1` | 加 `-BatchMode`, 跳過互動式建帳號 |
| `09_setup_portal.ps1` | 用本地 wheels (--no-index), 找不到也不卡死 |
| `install_offline.ps1` | 跑 04 自動帶 `-BatchMode` |

詳見 [PATCH_NOTE.md](PATCH_NOTE.md)。
