# SF Patch v1.0.0.6 — 快速使用

> 給「單獨下載這個 patch zip」的使用者看。詳細說明見 [PATCH_NOTE.md](PATCH_NOTE.md)。

---

## 解了什麼

1. Patch 可以**任意目錄跑** (舊 apply.ps1 必須在 SF root 結構下)
2. `install_openssh_portable.ps1` **自動找 OpenSSH-Win64.zip** (放當前目錄 / D:\install\ 都可以)
3. 新增 `fetch_openssh_portable.ps1` 給外網 PC 一鍵抓 + SHA256 校驗

---

## 三步驟用法

### 1️⃣ 外網 PC 抓 OpenSSH zip

```powershell
.\install_patch.ps1 -Here       # 先把 fetch 腳本拷到當前目錄
.\scripts\fetch_openssh_portable.ps1
# → 抓到當前目錄: OpenSSH-Win64.zip + OpenSSH-Win64.zip.sha256.txt
```

### 2️⃣ 拷到 USB, 帶進 SF 主機

把整個目錄 (含 scripts/ + OpenSSH-Win64.zip + sha256.txt) 拷進 SF 主機。

### 3️⃣ SF 主機驗 hash + 安裝

```powershell
# 驗 hash (對比 .sha256.txt 內的值)
Get-FileHash .\OpenSSH-Win64.zip -Algorithm SHA256

# 自動找 zip + 安裝
.\scripts\install_openssh_portable.ps1
```

---

## install_patch.ps1 三種模式

```powershell
.\install_patch.ps1                       # auto: 偵測 SF-PROJECT-ROOT
.\install_patch.ps1 -Here                 # 拷到當前目錄
.\install_patch.ps1 -Target 'C:\path\'    # 拷到指定目錄
```

---

## 我也想更新主腳本怎辦

如果你有完整 SF-PROJECT-ROOT (`sf_offline_bundle_*`):

```powershell
cd <SF-PROJECT-ROOT>
# 把這個 patch 整包 (含 install_patch.ps1 + files/) 拷進 patches/v1.0.0.6/
.\patches\v1.0.0.6\install_patch.ps1
# auto 偵測, 拷 scripts/ 進原專案
```

---

## 已知差別

- 舊 `apply.ps1` 還能用 (v1.0.0.1 ~ v1.0.0.5 都是)
- 新 `install_patch.ps1` 是 v1.0.0.6 起的標準, 未來 patch 沿用
