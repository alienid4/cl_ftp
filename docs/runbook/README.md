# Runbook — 操作指令歷史紀錄

每次給使用者執行的指令套組都歸檔到這裡, 方便事後重做、同事接手、故障排除。

## 命名規則

```
v<patch-版本>_<YYYYMMDD>_<HHMM>_<topic>.md
```

例:
- `v1.0.0.10_20260520_0830_linux_user_poc.md`
- `v1.0.0.11_20260521_1400_fix_https_cert.md`

## 結構

每份 runbook 包含:

1. **元資料表** (版本 / 日期 / 對象 / 預期結果 / 耗時)
2. **前提條件** (checklist)
3. **操作步驟** (照順序的 PowerShell 指令, 直接複製貼)
4. **預期結果** (跑完應該看到什麼)
5. **故障排除** (常見問題 + Linux 對照)
6. **附錄** (替代方案)

## 索引 (最新在上)

| 日期 | 版本 | 主題 | URL |
|---|---|---|---|
| 2026-05-20 08:30 | v1.0.0.10 | Linux 用戶 PoC 部署 (C:\, 無 HTTPS) | [v1.0.0.10_20260520_0830_linux_user_poc.md](v1.0.0.10_20260520_0830_linux_user_poc.md) |

## 對應其他文件

| 文件 | 用途 |
|---|---|
| [`../LINUX_USER_GUIDE.md`](../LINUX_USER_GUIDE.md) | Linux ↔ Windows 對照速查 |
| [`../startup_sop.md`](../startup_sop.md) | 安裝完成後啟動 8 步 SOP |
| [`../dev-log/issues_log.md`](../dev-log/issues_log.md) | 問題追蹤 (#001 ~ #023) |
| [`../../patches/README.md`](../../patches/README.md) | Patch 版本歷史 |

## 怎麼用 (給你)

每次跑 runbook:
1. 找對應主題的 .md 檔
2. 從上到下複製貼 PowerShell 指令
3. 跑出問題對照 Linux 同義指令

## 怎麼用 (給接手的同事)

照 runbook 跑就能重做整個部署, 不用問你細節。
