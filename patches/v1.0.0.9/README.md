# SF Patch v1.0.0.9 — 快速使用

> 路徑統一 (D:\_portal\ vs D:\DataExchange\) + 7 個 deploy 腳本 bug 修正。**必裝**。

## 一鍵套用

```
雙擊 run_patch.cmd
```

## 套完之後重跑流程

```powershell
cd C:\Users\xxx\Desktop\sf_offline_bundle_20260519_0901\deploy

# 重建目錄 (D:\_portal\ 跟 D:\DataExchange\ 都會建)
.\01_setup_directories.ps1

# 重設 ACL
.\02_setup_ntfs_acl.ps1

# 建 sftp_fin + sftp_ops (sftp_hr 會 skip)
.\04_create_sftp_accounts.ps1

# 重跑 SQL DB schema (現在 D:\_portal\db\ 存在了)
cd ..\
& "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\SQLCMD.EXE" -S .\SQLEXPRESS -E -i sql\01_create_db.sql

# Portal 部署 (現在能找到 Python)
cd deploy
.\09_setup_portal.ps1
```

## 修了什麼 (7 個)

| 檔 | 改了什麼 |
|---|---|
| `01_setup_directories.ps1` | 拆 DataRoot + PortalRoot, _portal 移到 D:\_portal\ |
| `02_setup_ntfs_acl.ps1` | 同樣拆 root |
| `04_create_sftp_accounts.ps1` | Description 縮短到 < 48 字元 |
| `06_install_iis.ps1` | PhysicalPath D:\_portal\app |
| `09_setup_portal.ps1` | Python 多重 fallback + 路徑修正 |
| `11_setup_firewall_log.ps1` | enum + netsh fallback (修 Error 87) |
| `12_install_ftps.ps1` | idempotent Add-WebConfiguration |

詳見 [PATCH_NOTE.md](PATCH_NOTE.md)。

## 還沒解的 (留給後續)

- URL Rewrite / ARR 看似已裝, exit code 是 warn 不阻塞
- HTTPS 綁定要 SSL 憑證 (公司申請後再裝)
- WinDefend 可能被公司 EDR 取代
- sshd warn 套 v1.0.0.8 後解
