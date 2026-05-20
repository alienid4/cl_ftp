# Patch v2.0.0.1 — 單一帳號 PoC + 非互動 + 對齊 u0X 主管圖

| 項目 | 值 |
|---|---|
| **版本** | v2.0.0.1 |
| **發布日期** | 2026-05-20 12:00 |
| **狀態** | ✅ 必裝 (使用者要求 PoC 單帳號) |
| **前置** | v2.0.0 (RHEL 主版) |

---

## 改了什麼

### 使用者需求

> "u01 改 u01t, 密碼 1qaz@WSX, 只建立一個帳號, shell 不用問, 目前沒有憑證"

對應 5 個調整:

| # | 需求 | 修法 |
|---|---|---|
| 1 | 帳號名 u01 → u01t | `SF_ACCOUNTS` 環境變數預設 `u01t` |
| 2 | 只建 1 個帳號 | 取代原本 HR/FIN/OPS 三個 |
| 3 | 密碼 = `1qaz@WSX` | 用 `SF_PASSWORD` 環境變數帶 (不寫死 source) |
| 4 | Shell 不用問 | 預設 `/sbin/nologin` (純 SFTP, 無 shell) |
| 5 | 沒憑證 = HTTP only | nginx 本來就 HTTP only, HTTPS template 註解 |

---

## 變更檔案

### 1. `deploy-rhel/01_setup_directories.sh`

舊: 建 `/data/exchange/{HR,FIN,OPS}/*`
新: 建 `/data/exchange/u01t/*` (對齊主管圖 u0X 業務代號模型)

支援多帳號: `SF_ACCOUNTS="u01 u02 u03"`

### 2. `deploy-rhel/02_setup_ownership.sh`

對齊新目錄結構, 並修正 SSH chroot 要求:
- chroot 點 (`/data/exchange/u01t/`) 必須 `root:root 0755`
- 子目錄 (`inbound/` 等) 給帳號可寫
- 加 setfacl 給 portal 服務帳號讀寫權

### 3. `deploy-rhel/04_create_sftp_accounts.sh` (大改)

舊:
- 預設建 `sftp_hr / sftp_fin / sftp_ops`
- 互動 prompt 密碼
- 沒明確 shell

新:
- 預設建 `u01t` (對齊主管圖)
- 密碼從 `SF_PASSWORD` 環境變數取
- shell 寫死 `/sbin/nologin` (純 SFTP)
- 不互動

### 4. `deploy-rhel/install_all.sh`

加環境變數:
```bash
SF_ACCOUNTS="u01t"          # 業務代號
SF_PASSWORD=""              # 密碼 (跑時帶)
```

### 5. `sql/01_create_db_postgres.sql`

`business_code` seed 從 u01/u02/u03 改成單一 u01t (PoC):
```sql
INSERT INTO business_code VALUES ('u01t', 'TEST', 'PoC 測試帳號', ...);
```

---

## 套用方式

```bash
cd /opt/sf
git pull
sudo ./deploy-rhel/install_all.sh   # 但密碼還沒帶
```

**正確用法 (帶密碼)**:

```bash
sudo SF_ACCOUNTS=u01t SF_PASSWORD='1qaz@WSX' ./deploy-rhel/install_all.sh
```

或單獨重跑 04 補密碼:

```bash
sudo SF_ACCOUNTS=u01t SF_PASSWORD='1qaz@WSX' ./deploy-rhel/04_create_sftp_accounts.sh
```

---

## 套完之後

### 驗證

```bash
# 1. 帳號存在
id u01t
# uid=1xxx(u01t) gid=xxx(sftp_users) groups=xxx(sftp_users)

# 2. 帳號家目錄
ls -la /data/exchange/u01t/
# drwxr-xr-x. root root .  (chroot 點)
# drwxrws---. u01t sftp_users inbound (帳號可寫)
# (略)

# 3. 從別台 PC 測 SFTP
sftp u01t@<sf-ip>
# 密碼: 1qaz@WSX
# 進去後 ls 看到 inbound/ pending/ outbound/ archive/ error/
```

### 上傳測試

```bash
# 別台 PC
echo "test" > test.txt
sftp u01t@<sf-ip> <<EOF
cd inbound
put test.txt
ls
quit
EOF

# SF 主機驗證
ls -la /data/exchange/u01t/inbound/
# 應該看到 test.txt
```

---

## 之後加帳號

```bash
sudo SF_ACCOUNTS="u02 u03" SF_PASSWORD='<random>' \
    ./deploy-rhel/04_create_sftp_accounts.sh

# 對應目錄也建
sudo SF_ACCOUNTS="u02 u03" \
    ./deploy-rhel/01_setup_directories.sh
sudo SF_ACCOUNTS="u02 u03" \
    ./deploy-rhel/02_setup_ownership.sh
```

或修改 `install_all.sh` 內 `SF_ACCOUNTS` 預設值。

---

## 為什麼帳號叫 u01t 不叫 u01

| 命名 | 含意 |
|---|---|
| `u01` | 正式業務代號 (對齊主管圖) |
| **`u01t`** | **PoC 測試帳號** (`t` = test) |

之後正式上線時:
- 新建 u01 / u02 / u03 (對齊主管圖)
- u01t 留著當 IT 測試帳號 (或刪掉)

---

## 為什麼 shell = /sbin/nologin

| 用戶類型 | 適合 shell |
|---|---|
| 互動用戶 (IT 維運) | `/bin/bash` |
| **SFTP only (本帳號)** | **`/sbin/nologin`** |
| 完全停用 | `/bin/false` |

對 SFTP only 帳號用 `/sbin/nologin`:
- 不能 ssh login shell
- 可以 SFTP (sshd Match Group sftp_users + ForceCommand internal-sftp)
- 安全: 即使密碼洩漏也不能 ssh

對應主管圖「業務代號帳號拒絕互動式登入」要求。

---

## 為什麼密碼不寫死 source

`1qaz@WSX` 是預設 PoC 密碼, 但**不寫進 git source**, 理由:

1. **Public repo**: 寫死等於把密碼公開到網路
2. **規範鐵律 6**: 真實密碼絕對不進 public repo
3. **彈性**: 正式時換密碼不用改 source

用環境變數 `SF_PASSWORD='1qaz@WSX'` 跑時帶, 只在你 SF 主機 shell history 有, 不在 git。

之後 PAM 接管時, `SF_PASSWORD` 改從 PAM API 取:
```bash
SF_PASSWORD=$(pam-cli get-secret /sf/u01t)
sudo -E ./deploy-rhel/04_create_sftp_accounts.sh
```

---

## 相關連結

- 對應 runbook: [v2.0.0.1_20260520_1200_single_account_poc.md](../../docs/runbook/v2.0.0.1_20260520_1200_single_account_poc.md)
- v2.0.0 主版: [PATCH_NOTE](../v2.0.0/PATCH_NOTE.md)
