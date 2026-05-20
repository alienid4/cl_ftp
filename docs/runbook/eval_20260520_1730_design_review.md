# 設計評估: 為什麼移植不順 + 改善方案

| 項目 | 內容 |
|---|---|
| **類型** | eval (架構反思 / 決策) |
| **日期** | 2026-05-20 17:30 |
| **觸發** | 使用者: 「我覺得移植到公司內部問題很多, 很不順, 是我的方法有問題嗎?」 |
| **結論** | **不是使用者問題, 是 Claude 設計太複雜**. 給 3 條更好的路 |

---

## 對話歷史 (痛點)

### v1.x Windows (10 個 patch)
- BOM, NSSM 503, IIS+ARR, SQL Express CHT/ENU, Python wheels...
- 卡了 2 天 Portal 還沒跑起來

### v2.0 RHEL (10 個 patch)
- Rocky 9.7 vs RHEL 9.6 file conflict
- redhat-release / openssl-fips-provider / crypto-policies 連環坑
- 每加一個 EXCLUDE, 撞下一個

### 共通本質
**打包機 ≠ 目標機** + **離線 bundle 反 dnf 設計** = 必然踩坑。

---

## 3 個更好的方案 (按推薦度)

### 🥇 路 A: 用公司 yum mirror

**問 IT**:
- 「公司有 RHEL/Rocky 內網 yum mirror 嗎?」
- 90% 公司有 (RHEL Satellite / Spacewalk / Nexus / 自架 createrepo)

**好處**:
- SF 主機自己 `dnf install`, dnf 解 dependency
- 沒 file conflict (因為主機跟 mirror 是同版 RHEL)
- 不用打 bundle, 不用 EXCLUDE_PATTERN

**簡化的部署**:
```bash
sudo dnf install -y postgresql-server nginx samba python3 chrony
git clone https://corp-git.local/sf  # 或內網 GitLab
cd sf && sudo ./deploy-rhel/install_all.sh
```

→ **完全沒有當前對話遇到的所有坑**。

### 🥈 路 B: Podman container

**好處**:
- SF 主機只裝 podman (1 個 RPM)
- Portal + DB 跑 container, 隔離乾淨
- 升級 = 換 image, 不污染 base system
- RHEL 9 內建 podman, 公司 mirror 有

**部署**:
```bash
# 主機只裝 podman
sudo dnf install -y podman

# Portal (container)
sudo podman run -d --name sf-portal -p 5000:5000 \
    -v /data/exchange:/data \
    ghcr.io/alienid4/sf-portal:latest

# DB (container)
sudo podman run -d --name sf-postgres \
    -e POSTGRES_DB=file_exchange_audit \
    -e POSTGRES_USER=portal \
    -e POSTGRES_PASSWORD=xxx \
    -v sf-pgdata:/var/lib/postgresql/data \
    -p 127.0.0.1:5432:5432 \
    docker.io/postgres:16
```

**沒 file conflict 問題** (container 內外隔離)。

### 🥉 路 C: Ansible from jumphost

**好處**:
- 你 Windows PC 開 WSL / 跑 ansible
- 改 playbook 即時生效, 不用 USB
- 可同時管多台 SF 主機 (inventory.ini)

**結構**:
```
你 PC (Ansible)
    ↓ ssh push
SF 主機 (dnf install from 公司 mirror)
```

---

## 比較表

| 維度 | 🥇 yum mirror | 🥈 Podman | 🥉 Ansible | ❌ 離線 bundle (現在的) |
|---|---|---|---|---|
| 撞 file conflict 機率 | 0% | 0% | 0% | **100%** |
| 改設定後立即生效 | ✓ | ✓ (rebuild image) | ✓ | ❌ (重打 bundle) |
| 你要做的事 | 跟 IT 要 mirror | 跟 IT 要 registry | 你 PC 裝 ansible | 我這邊打 + 你 USB |
| 維護成本 | 低 | 最低 | 中 | **最高 (debug 連環坑)** |
| 對使用者 (Linux 背景) | 標準作法 | 你最熟 | 你熟 | 反 Linux 哲學 |
| 公司 IT 接受度 | ✓ | ✓ | ✓ | ⚠️ (像走私) |

---

## 我建議使用者做的 3 步

### Step 1: 跟 IT 問環境問卷

```
1. 公司有 RHEL 內網 yum mirror 嗎? URL ____
2. 公司有 container registry (Harbor / Nexus / GitLab Registry)? URL ____
3. SF 主機 ssh 22 能從一台跳板 PC 連嗎?
4. SF 主機可不可裝 podman?
```

任一答 yes → 對應切方案。

### Step 2: 短期先把 v2.0.0.10 跑完

「有一台能 demo 的環境」優先, 用現有 bundle 跑通。
這是 throwaway PoC, 不是正式架構。

### Step 3: 切到 🥇/🥈/🥉 之一

切完後**正式部署不用再打 patch v2.0.0.11/12/...**, 架構本身對。

---

## 寫進 SKILL (鐵律 10/11)

已寫進 `docs/dev-log/skill_sf_workflow.md`:
- **鐵律 10**: Pull 模式優於 Push 打包
- **鐵律 11**: 開工前評估公司既有基礎設施

避免未來再踩同樣坑。

---

## 對使用者的話 (honest assessment)

> 「不是你方法問題, 是我設計太複雜。我從 Windows 直接複製打包思維到 RHEL, 違反了 Linux pull-based 慣例。打包機 (Rocky 9.7) 跟你主機 (RHEL 9.6) 必然踩 file conflict。」
>
> 「短期把 v2.0.0.10 跑完有個能 demo 的環境, 中期切到 yum mirror / Podman / Ansible 任一條, 之後就不會再有當前的痛。」

---

## 相關連結

- [SKILL 鐵律 10/11](../dev-log/skill_sf_workflow.md)
- [v2.0.0.10 PATCH_NOTE](../../patches/v2.0.0.10/PATCH_NOTE.md) (短期解)
- [eval RHEL 替代方案 (Windows → RHEL)](eval_20260520_0900_rhel_alternative.md)
