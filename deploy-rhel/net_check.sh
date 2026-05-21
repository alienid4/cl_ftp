#!/bin/bash
# net_check.sh — 純診斷 SF 主機能連到哪些網域 (不裝任何東西)
# 用法: bash net_check.sh
#   或在能連 github 的機器跑: curl -fsSL https://github.com/alienid4/cl_ftp/raw/main/deploy-rhel/net_check.sh | sudo bash

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[ OK ]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; }

echo ""
echo -e "${CYAN}=== SF 主機網路連通性檢查 ===${NC}"
echo ""

# 1. 對外連通 (一般網路)
echo "1. 一般外網:"
for host in 8.8.8.8 1.1.1.1; do
    if timeout 3 bash -c ">/dev/tcp/$host/443" 2>/dev/null; then
        ok "$host:443 可達"
    else
        fail "$host:443 連不到"
    fi
done

# 2. GitHub (本次 patch 用到)
echo ""
echo "2. GitHub:"
for host in github.com raw.githubusercontent.com codeload.github.com objects.githubusercontent.com; do
    if timeout 3 bash -c ">/dev/tcp/$host/443" 2>/dev/null; then
        ok "$host:443 可達"
    else
        fail "$host:443 連不到"
    fi
done

# 3. 公司 Satellite / RHEL repo
echo ""
echo "3. RHEL repo (公司 mirror):"
if dnf repolist enabled 2>/dev/null | tail -5; then
    ok "dnf repolist 可跑"
fi

# 4. curl 試抓一個小檔
echo ""
echo "4. curl 試抓 GitHub raw (5 秒 timeout):"
if curl -fsSL --max-time 5 -o /dev/null https://github.com/alienid4/cl_ftp/raw/main/README.md 2>&1; then
    ok "curl github raw 成功"
else
    fail "curl github raw 失敗 — SF 真的連不到 github"
fi

echo ""
echo "把這個輸出截圖給 Claude, 決定走哪條路:"
echo "  - 全部 OK    → fix_portal.sh curl github 可行"
echo "  - 都連不到   → 必須先在 PC 抓 tar, 拷到 SF /opt/sf/release-zip/"
