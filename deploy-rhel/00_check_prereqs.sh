#!/bin/bash
# 前置檢查 — RHEL 版
# 對應 Windows: deploy/00_check_prereqs.ps1
set -euo pipefail

ok()   { echo -e "[ OK ]  $*"; }
fail() { echo -e "[FAIL]  $*"; exit 1; }

echo "=== SF 主機前置檢查 ==="
echo ""

# 1. root 權限
[[ $EUID -eq 0 ]] && ok "root 權限" || fail "不是 root"

# 2. RHEL 版本
if grep -qE 'release [89]' /etc/redhat-release 2>/dev/null; then
    ok "OS: $(cat /etc/redhat-release)"
else
    fail "不是 RHEL 8/9: $(cat /etc/redhat-release 2>/dev/null || echo unknown)"
fi

# 3. 記憶體 >= 4 GB
mem_gb=$(awk '/MemTotal/{printf "%.1f", $2/1024/1024}' /proc/meminfo)
if (( $(echo "$mem_gb >= 4" | bc -l 2>/dev/null || echo 0) )); then
    ok "記憶體 ${mem_gb} GB"
else
    echo "[warn] 記憶體 ${mem_gb} GB (建議 >= 4 GB)"
fi

# 4. 磁碟空間
disk_gb=$(df -BG /opt 2>/dev/null | awk 'NR==2 {gsub(/G/,""); print $4}')
if [[ "${disk_gb:-0}" -ge 30 ]]; then
    ok "/opt 可用空間 ${disk_gb} GB"
else
    echo "[warn] /opt 可用空間 ${disk_gb:-?} GB (建議 >= 30 GB)"
fi

# 5. SELinux
selinux=$(getenforce 2>/dev/null || echo "Disabled")
if [[ "$selinux" == "Enforcing" ]]; then
    ok "SELinux: $selinux (建議保持)"
else
    echo "[warn] SELinux: $selinux (建議 Enforcing)"
fi

# 6. 網路連通 (dnf 用)
if ping -c1 -W2 8.8.8.8 &>/dev/null || ping -c1 -W2 mirrors.example.com &>/dev/null; then
    ok "網路: 可達"
else
    echo "[warn] 網路: 不通 (離線安裝模式)"
fi

# 7. dnf 可用
command -v dnf &>/dev/null && ok "dnf 可用" || fail "找不到 dnf"

# 8. AD DNS 解析 (如果指定要接 AD)
if [[ "${SF_SKIP_AD:-1}" == "0" ]]; then
    if host -t SRV _kerberos._tcp.${SF_AD_DOMAIN:-corp.local} &>/dev/null; then
        ok "AD DNS 解析: ${SF_AD_DOMAIN:-corp.local}"
    else
        echo "[warn] 找不到 AD DNS, 確認 /etc/resolv.conf 指向公司 DNS"
    fi
fi

echo ""
echo "前置檢查通過"
