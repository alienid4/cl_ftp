#!/bin/bash
#
# v2.0.0.6 patch apply (對齊 SKILL 鐵律 3)
# 對應 Windows v1.x 的 install_patch.ps1
#
# 用法:
#   雙擊 / sudo bash apply.sh        (auto-find sf-bundle/)
#   sudo bash apply.sh -DryRun       (預演)
#   sudo bash apply.sh -Target /path (指定 sf-bundle 目錄)
#
set -euo pipefail

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
step()  { echo ""; echo -e "${CYAN}=== $* ===${NC}"; }
ok()    { echo -e "${GREEN}[ok]${NC} $*"; }
warn()  { echo -e "${YELLOW}[warn]${NC} $*"; }
fail()  { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }

# Parse args
DRYRUN=0
TARGET=""
while [[ $# -gt 0 ]]; do
    case $1 in
        -DryRun|--dry-run|-n) DRYRUN=1; shift ;;
        -Target|--target|-t) TARGET="$2"; shift 2 ;;
        -h|--help)
            grep -E '^#( |$)' "$0" | sed 's/^# \?//'
            exit 0 ;;
        *) fail "未知參數: $1" ;;
    esac
done

# 偵測腳本位置 (在 cd 之前)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH_FILES="$SCRIPT_DIR/files"

step "v2.0.0.6 Patch — install_offline.sh skip-broken fix"

# === 1. 偵測 sf-bundle 位置 ===
if [[ -n "$TARGET" ]]; then
    if [[ ! -d "$TARGET" ]]; then
        fail "Target 不存在: $TARGET"
    fi
    SF_BUNDLE="$TARGET"
    echo "[mode] -Target: $SF_BUNDLE"
else
    # 自動掃常見位置
    CANDIDATES=(
        "$(pwd)/sf-bundle"
        "$(pwd)/../sf-bundle"
        "/opt/install/sf-bundle"
        "/tmp/sf-bundle"
        "$HOME/sf-bundle"
        "$HOME/Downloads/sf-bundle"
    )
    SF_BUNDLE=""
    for c in "${CANDIDATES[@]}"; do
        if [[ -f "$c/install_offline.sh" ]]; then
            SF_BUNDLE="$(cd "$c" && pwd)"
            echo "[auto] 找到 sf-bundle: $SF_BUNDLE"
            break
        fi
    done

    if [[ -z "$SF_BUNDLE" ]]; then
        fail "找不到 sf-bundle/ 目錄, 用 -Target /path 指定"
    fi
fi

# === 2. 確認 patch files 存在 ===
NEW_FILE="$PATCH_FILES/install_offline.sh"
if [[ ! -f "$NEW_FILE" ]]; then
    fail "patch 檔不存在: $NEW_FILE"
fi
ok "Patch 來源: $NEW_FILE"

# === 3. 比對 SHA256 (idempotent: 已是最新就 skip) ===
TARGET_FILE="$SF_BUNDLE/install_offline.sh"
NEW_HASH=$(sha256sum "$NEW_FILE" | awk '{print $1}')

if [[ -f "$TARGET_FILE" ]]; then
    OLD_HASH=$(sha256sum "$TARGET_FILE" | awk '{print $1}')
    if [[ "$NEW_HASH" == "$OLD_HASH" ]]; then
        ok "已是最新版 (SHA256 一致, skip): $TARGET_FILE"
        echo ""
        echo "→ 可直接重跑 install_offline.sh:"
        echo "  cd $SF_BUNDLE && sudo SF_ACCOUNTS=u01t SF_PASSWORD='1qaz@WSX' ./install_offline.sh"
        exit 0
    fi

    # === 4. 備份原檔 ===
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP="$TARGET_FILE.bak.$TIMESTAMP"
    if [[ "$DRYRUN" -eq 1 ]]; then
        echo "[dry] cp $TARGET_FILE $BACKUP"
    else
        cp "$TARGET_FILE" "$BACKUP"
        ok "原檔備份至: $BACKUP"
    fi
fi

# === 5. 套用 ===
if [[ "$DRYRUN" -eq 1 ]]; then
    echo "[dry] cp $NEW_FILE $TARGET_FILE"
    echo ""
    echo "DryRun 結束, 沒有變更"
else
    cp "$NEW_FILE" "$TARGET_FILE"
    chmod +x "$TARGET_FILE"
    ok "Patch 套用: $TARGET_FILE"

    echo ""
    echo "驗證:"
    grep 'skip-broken' "$TARGET_FILE" && ok "已含 --skip-broken" || warn "驗證失敗"
fi

# === 6. 下一步 ===
echo ""
step "下一步"
echo "  cd $SF_BUNDLE"
echo "  sudo SF_ACCOUNTS=u01t SF_PASSWORD='1qaz@WSX' ./install_offline.sh"
echo ""
echo "對應 Linux: sed -i 'fix' install_offline.sh (但 apply.sh 有 idempotent + 備份)"
