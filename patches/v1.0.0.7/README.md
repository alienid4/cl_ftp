# SF Patch v1.0.0.7 — 快速使用

> 修 v1.0.0.5/v1.0.0.6 部署後新發現的 5 個 bug。**必裝**。

## 一鍵套用

```
雙擊 run_patch.cmd
```

或 PowerShell:
```powershell
.\install_patch.ps1
```

腳本會自動找你桌面的 sf_offline_bundle_*, 詢問確認, 拷 5 個檔覆蓋。

## 套用後重跑

```powershell
cd C:\Users\xxx\Desktop\sf_offline_bundle_20260519_0901
.\deploy\offline\install_offline.ps1
# 預期: summary 全 ok / skip, 不再有紅字
# OpenSSH.Server 行從 fail → skip 「已安裝 (portable, sshd Running)」

.\scripts\health_check.ps1
# 預期: NTP / Defender 病毒碼 不再 crash
```

## 修了什麼

1. `00_check_prereqs.ps1` D: 磁碟門檻 100 → 30 GB (97.4 GB 不再 FAIL)
2. `01_setup_directories.ps1` PS 5.1 解析錯誤 (Join-Path 加雙括號)
3. `03_install_openssh.ps1` portable OpenSSH 偵測 (sshd service 存在就 skip)
4. `install_offline.ps1` Step 7 同樣 portable 偵測
5. `health_check.ps1` 兩處 null/type 崩潰 (NTP + Defender)

詳細見 [PATCH_NOTE.md](PATCH_NOTE.md)。

## 還沒解的

下面這些是「業務狀態」, 不是腳本 bug, 留給 startup_sop 8 步流程處理:

- WinDefend service Stopped → Step 13 啟用
- AuditLog DB 連線 fail → Step 5 建 DB schema
- SF_DailyBackup 從沒跑過 → 設定排程後就 ok
