# Patch v1.0.0.10 — sshd 啟動修 + 04 BatchMode + 09 wheels offline

| 項目 | 內容 |
|---|---|
| **Patch 編號** | v1.0.0.10 |
| **發布日期** | 2026-05-20 |
| **狀態** | ✅ 必裝 (修 sshd 仍啟動失敗 + 帳號可延後 + Portal 離線安裝) |

---

## 解了什麼

### 修 #1: `config/sshd_config` — sshd 啟動失敗的根因

v1.0.0.8 改了 Subsystem + Banner 但 sshd 還是啟動 fail。再深挖找到 2 個:

1. `DenyUsers Administrator administrator **SF\Administrator**` — `SF\Administrator` 在工作群組電腦 (沒加 SF domain) 不存在, sshd 解析時 fail
2. `Match User Administrator` 區塊 — Administrator 已 DenyUsers, 不需要 Match (有衝突)

**修法**:
- DenyUsers 拿掉 `SF\Administrator`
- 註解掉 `Match User Administrator` 區塊

### 修 #2: `deploy/04_create_sftp_accounts.ps1` — `-BatchMode` 跳過互動

install_offline.ps1 跑到 04 會卡在 prompt 等密碼。**第一階段** (PoC / AP 系統還沒接) 不需要建帳號。

**修法**: 04 加 `-BatchMode` switch:
- `-BatchMode` 且沒帶 `-Passwords` → skip 整個建帳號流程
- install_offline.ps1 Step 9 跑 04 時帶 `-BatchMode`
- 之後手動建帳號: `.\04_create_sftp_accounts.ps1` (不帶 -BatchMode 即進互動)

### 修 #3: `deploy/09_setup_portal.ps1` — 離線 pip + skip 防卡死

內網無外網, `pip install` 連 pypi.org 超時卡死。

**修法**:
1. 多路徑自動找 `python_wheels/` 目錄
2. 找到 → `pip install --no-index --find-links <wheels>` (純離線)
3. 找不到 → skip + 給明確「外網 PC 怎麼準備 wheels」指引, 不卡死

### 修 #4: `deploy/offline/install_offline.ps1` Step 9 — 04 自動跑 -BatchMode

```powershell
if ($s.Name -like '04_create_sftp_accounts*') {
    & $s.FullName -BatchMode
}
```

---

## 套用方式

雙擊 `run_patch.cmd` 或 `.\install_patch.ps1`。

## 套完之後 (3 步)

```powershell
# 1. 重啟 sshd 用新 sshd_config
cd <sf_bundle>\deploy
.\03_install_openssh.ps1
# 預期: [ok] sshd 重啟 (不再 fail)

# 或手動驗 sshd_config 語法 + restart:
& 'C:\Program Files\OpenSSH\sshd.exe' -t -f 'C:\ProgramData\ssh\sshd_config'
Restart-Service sshd
Get-Service sshd

# 2. 重跑 09 (現在 wheels 找不到不會卡死)
.\09_setup_portal.ps1

# 3. 重跑 install_offline 確認整體 ok (04 自動 skip)
cd offline
.\install_offline.ps1
```

---

## 還沒解的: Python wheels 沒打進 bundle

09 套了 patch 後不卡死, 但 Portal Python 套件 (Flask / waitress / pyodbc) 還沒裝。

要在**外網 PC** 跑:
```powershell
# 外網 PC, 抓 wheels
mkdir python_wheels
pip download -d python_wheels -r portal\requirements.txt
# 約 36 個 wheels, 16 MB
# USB 拷到 SF 主機 D:\install\python_wheels\
```

然後在 SF 主機重跑 `.\09_setup_portal.ps1`, 就會用 `D:\install\python_wheels` 離線安裝。
