# Patch v2.0.0.3 — Windows PC 打包工具 (Docker + Rocky 9)

| 項目 | 值 |
|---|---|
| **版本** | v2.0.0.3 |
| **發布日期** | 2026-05-20 15:00 |
| **狀態** | ✅ 必裝 (使用者只有 Windows PC 能上網) |

---

## 使用者場景

> "我內網不能下載, 我只能透過 PC 下載"

使用者只有 Windows PC 能上網, SF 主機 RHEL 在內網。v2.0.0.2 提供的 `build_offline_bundle.sh` 要在 RHEL 跑, 但使用者沒外網 RHEL 機器。

→ 需要 **Windows PC 上的打包方案**。

---

## 解法: Docker on Windows

Windows PC 裝 Docker Desktop (一次性), 用一個 PowerShell 腳本:
- 跑 Rocky Linux 9 container
- container 內跑 `dnf download` + `pip download` + `git clone`
- 輸出 tar.gz 到 Windows PC 桌面

之後 USB 拷到 SF 主機跑 `install_offline.sh`。

對應 Linux 工程師熟悉的概念:
```bash
# 在你熟悉的 Linux:
ssh build-server "dnf download foo && tar czf - foo" > bundle.tar.gz

# 在 Windows + Docker 等價:
docker run --rm -v ${PWD}:/output rockylinux:9 bash -c "..."
```

---

## 新增 1 個檔

### `scripts/build_bundle_windows.ps1`

PowerShell 腳本, 在 Windows PC 跑:

1. 檢查 Docker Desktop 存在 + daemon 跑著
2. 確保 Rocky Linux 9 image 已拉 (`docker pull`)
3. `docker run` 跑 container:
   ```bash
   dnf install git python3-pip
   git clone https://github.com/alienid4/cl_ftp
   bash ./deploy-rhel/build_offline_bundle.sh /output/sf-rhel-bundle
   ```
4. 輸出 `sf-rhel-bundle-YYYYMMDD_HHMM.tar.gz` 到 Windows PC 當前目錄
5. 顯示 SHA256 + 下一步指引

---

## 套用方式 (Windows PC)

```powershell
# 1. 確保 Docker Desktop 跑著
docker version

# 2. 抓腳本
cd $env:USERPROFILE\Desktop
iwr https://raw.githubusercontent.com/alienid4/cl_ftp/main/scripts/build_bundle_windows.ps1 -OutFile build.ps1

# 3. 跑
.\build.ps1
```

輸出:
```
sf-rhel-bundle-20260520_1500.tar.gz (225M)
sf-rhel-bundle-20260520_1500.tar.gz.sha256
```

---

## 替代方案 (沒 Docker Desktop 時)

詳見 runbook [v2.0.0.3_20260520_1500_windows_pc_build.md](../../docs/runbook/v2.0.0.3_20260520_1500_windows_pc_build.md):

### 方案 A: WSL2 + Ubuntu (Windows 內建)
- `wsl --install -d Ubuntu`
- Ubuntu 內裝 dnf + 加 Rocky repo
- 跑 build_offline_bundle.sh

### 方案 B: VirtualBox + Rocky Linux ISO
- 全 GUI, 純免費, 不用 Docker / WSL
- 起 VM, 內 clone repo + 跑 build

---

## 為什麼用 Docker 而不是 WSL / VM

| 方式 | 優點 | 缺點 |
|---|---|---|
| **Docker Desktop** | 5 分鐘設好, 之後重打包都快, 隔離乾淨 | 公司 PC 可能擋 |
| WSL2 | Windows 內建, 不用裝額外軟體 | 設 RHEL repo 有點繁瑣 |
| VirtualBox | 完全免費, 公司通常不擋 | 起 VM 30 分鐘, GUI 操作慢 |

預設方案: **Docker** (公司有給 Linux 工程師通常會給 Docker)。
備案: WSL / VirtualBox。

---

## 為什麼用 Rocky Linux 9 不直接用 RHEL 9

- **RHEL 9 image** 要 Red Hat subscription
- **Rocky Linux 9** 是 RHEL 9 的免費 clone, RPM 100% 通用
- Docker Hub 直接可拉 (`docker pull rockylinux:9`)

打包出來的 RPM 在 RHEL 9 主機可以直接 install (因為 Rocky = RHEL clone)。

---

## 完整流程圖

```
[Windows PC]                             [SF 主機 RHEL 內網]
─────────────                           ────────────────────
1. cd Desktop
2. iwr build.ps1                         
3. .\build.ps1                           
   → Docker Desktop 起 Rocky 9          
   → container 內跑 build_offline_bundle
   → 輸出 sf-rhel-bundle-XXXXX.tar.gz   
4. 拷 USB                  ──USB──►   1. mount /dev/sdb1 /mnt/usb
                                       2. sha256sum -c
                                       3. tar xzf ... -C /opt/install
                                       4. sudo ./install_offline.sh
                                       5. http://<IP>/ 訪問
```

---

## 影響檔案

| 檔案 | 動作 |
|---|---|
| `scripts/build_bundle_windows.ps1` | 新增 (Windows PC 端) |
| (其他不變, 沿用 v2.0.0.2 的 `build_offline_bundle.sh`) | |

---

## 相關連結

- 完整 SOP: [v2.0.0.3_20260520_1500_windows_pc_build.md](../../docs/runbook/v2.0.0.3_20260520_1500_windows_pc_build.md)
- 對應 Linux build script: [v2.0.0.2 PATCH_NOTE](../v2.0.0.2/PATCH_NOTE.md)
- 對應 Windows v1.x: 同樣概念但工具不同 (PowerShell + msiexec → PowerShell + Docker)
