#!/bin/bash
#
# SF File Exchange Server - RHEL Offline Bundle Builder
#
# 在「有外網的 RHEL 8/9 PC」跑這支, 抓所有 SF 需要的 RPM + Python wheels + repo,
# 打包成 tarball, USB 拷到 SF 主機 (無外網) 跑 install_offline.sh
#
# 對應 Windows: deploy/offline/build_offline_bundle.ps1
#
# 用法:
#   ./build_offline_bundle.sh                    # 預設 /tmp/sf-rhel-bundle
#   ./build_offline_bundle.sh /home/me/bundle    # 指定輸出目錄
#

set -euo pipefail

OUTPUT_DIR="${1:-/tmp/sf-rhel-bundle}"
TIMESTAMP=$(date +%Y%m%d_%H%M)
BUNDLE_NAME="sf-rhel-bundle-${TIMESTAMP}"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

step()  { echo ""; echo -e "${CYAN}=== $* ===${NC}"; }
ok()    { echo -e "${GREEN}[ok]${NC} $*"; }
warn()  { echo -e "${YELLOW}[warn]${NC} $*"; }

# 0. 前置檢查
[[ $EUID -eq 0 ]] || warn "建議用 root (root 跑 dnf download 比較順)"

if ! grep -qE 'release [89]' /etc/redhat-release 2>/dev/null; then
    warn "不在 RHEL 8/9 (打包出來的 RPM 可能跟 SF 主機不相容)"
fi

# 確認外網
if ! ping -c1 -W2 8.8.8.8 &>/dev/null; then
    warn "ping 8.8.8.8 不通, 確認此機有外網"
fi

# 確認工具
for tool in dnf pip3 git tar; do
    command -v $tool &>/dev/null || { echo "[FAIL] 缺工具: $tool"; exit 1; }
done

mkdir -p "$OUTPUT_DIR"/{rpms,wheels,repo,scripts}
cd "$OUTPUT_DIR"

step "1. 抓 RPM 套件 (含 deps)"
cd rpms

# 啟用 EPEL repo (有些套件像 mailx / s-nail 在 EPEL)
dnf install -y epel-release 2>&1 | tail -3 || warn "EPEL 安裝跳過"

# 套件清單 (對應 deploy-rhel/*.sh 內 dnf install 的所有套件)
# 分批抓, 個別失敗不影響其他
RPM_GROUPS=(
    # 基本工具
    "git curl wget tar unzip bzip2 vim-enhanced bc openssl which"

    # OpenSSH (RHEL 預裝, 但保險起見)
    "openssh openssh-server openssh-clients"

    # PostgreSQL
    "postgresql postgresql-server postgresql-contrib python3-psycopg2"

    # Web (nginx + Python)
    "nginx python3 python3-pip python3-virtualenv python3-setuptools"

    # Samba
    "samba samba-common samba-client cifs-utils"

    # NTP
    "chrony"

    # 監控 + 告警 (s-nail 取代 mailx in RHEL 9)
    "sysstat audit"

    # AD 整合 (07_join_ad.sh 用)
    "realmd sssd sssd-tools adcli samba-common-tools krb5-workstation"
    "oddjob oddjob-mkhomedir authselect"

    # 防火牆
    "firewalld"
)

# 額外: mail 工具 (RHEL 8 用 mailx, RHEL 9 改 s-nail)
OPTIONAL_RPMS=(
    "mailx s-nail"
)

echo "RPM 群組總數: ${#RPM_GROUPS[@]}"
echo ""
echo "下載中 (約 200-300 MB)..."

FAILED_GROUPS=()
for group in "${RPM_GROUPS[@]}"; do
    echo ">>> 抓: $group"
    if ! dnf download --resolve --alldeps --downloaddir="$(pwd)" $group 2>&1 | tail -3; then
        warn "群組失敗: $group"
        FAILED_GROUPS+=("$group")
    fi
done

# Optional (有就好, 沒有不擋)
for group in "${OPTIONAL_RPMS[@]}"; do
    echo ">>> 可選: $group"
    dnf download --resolve --alldeps --downloaddir="$(pwd)" $group 2>&1 | tail -3 || warn "可選套件 $group 找不到"
done

if [[ ${#FAILED_GROUPS[@]} -gt 0 ]]; then
    warn "${#FAILED_GROUPS[@]} 個套件群組抓失敗 (但繼續打包):"
    printf '  - %s\n' "${FAILED_GROUPS[@]}"
fi

RPM_COUNT=$(ls *.rpm 2>/dev/null | wc -l)
RPM_SIZE=$(du -sh . 2>/dev/null | awk '{print $1}')
ok "抓到 $RPM_COUNT 個 RPM, 共 ${RPM_SIZE:-0}"

if [[ "$RPM_COUNT" -lt 50 ]]; then
    warn "RPM 數量異常少 ($RPM_COUNT), 預期 > 100. 可能 dnf repo 沒設好"
fi

step "2. 抓 Python wheels (Portal 用)"
cd "$OUTPUT_DIR/wheels"

# 對應 portal/requirements.txt
PIP_PACKAGES=(
    flask
    waitress
    gunicorn
    psycopg2-binary
    python-ldap
    ldap3
    requests
    cryptography
    flask-login
    flask-session
    pyjwt
    werkzeug
)

echo "Python 套件:"
printf '  %s\n' "${PIP_PACKAGES[@]}"
echo ""

pip3 download --dest "$(pwd)" "${PIP_PACKAGES[@]}" 2>&1 | tail -5

WHL_COUNT=$(ls *.whl *.tar.gz 2>/dev/null | wc -l)
WHL_SIZE=$(du -sh . | awk '{print $1}')
ok "抓到 $WHL_COUNT 個 wheels, 共 $WHL_SIZE"

step "3. 拷 repo (從本地 OR 從 GitHub clone)"
cd "$OUTPUT_DIR/repo"

# 偵測是否在 repo 目錄內跑 (CI / 本地 dev)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_REPO="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$LOCAL_REPO/portal/wsgi.py" ]]; then
    echo "[info] 從本地 repo 拷 ($LOCAL_REPO)"
    # 排除 .git, release-zip, output, .github 等
    rsync -a \
        --exclude='.git' \
        --exclude='release-zip' \
        --exclude='output' \
        --exclude='node_modules' \
        --exclude='__pycache__' \
        "$LOCAL_REPO/" .
    REPO_VER=$(cd "$LOCAL_REPO" && git describe --tags --always 2>/dev/null || echo local)
else
    echo "[info] 本地沒 repo, 從 GitHub clone"
    git clone --depth=1 https://github.com/alienid4/cl_ftp .
    REPO_VER=$(git describe --tags --always 2>/dev/null || echo unknown)
    rm -rf .git
fi
ok "Repo 就位 (version: $REPO_VER)"

step "4. 寫 install_offline.sh (給 SF 主機跑)"
cat > "$OUTPUT_DIR/install_offline.sh" <<'INSTALLEOF'
#!/bin/bash
#
# SF File Exchange Server - RHEL Offline Installer
# 在 SF 主機 (無外網) 跑這支
#
# 用法 (Step 1 + Step 2 + Step 3):
#   sudo ./install_offline.sh
#
#   或帶帳號密碼:
#   sudo SF_ACCOUNTS=u01t SF_PASSWORD='1qaz@WSX' ./install_offline.sh
#

set -euo pipefail
BUNDLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'
step()  { echo ""; echo -e "${CYAN}=== $* ===${NC}"; }
ok()    { echo -e "${GREEN}[ok]${NC} $*"; }

[[ $EUID -eq 0 ]] || { echo "[FAIL] 請用 sudo"; exit 1; }

step "Step 1: 安裝 RPM (離線, 用 bundle 內的)"
if [[ -d "$BUNDLE_DIR/rpms" ]] && ls "$BUNDLE_DIR/rpms"/*.rpm &>/dev/null; then
    echo "RPM 數量: $(ls $BUNDLE_DIR/rpms/*.rpm | wc -l)"
    dnf install -y --disablerepo='*' "$BUNDLE_DIR"/rpms/*.rpm 2>&1 | tail -5
    ok "RPM 安裝完成"
else
    echo "[skip] $BUNDLE_DIR/rpms 沒有 RPM, 跳過"
fi

step "Step 2: 拷 repo 到 /opt/sf"
mkdir -p /opt/sf
if [[ -d "$BUNDLE_DIR/repo" ]]; then
    cp -r "$BUNDLE_DIR/repo/"* /opt/sf/
    ok "Repo 拷到 /opt/sf"
fi

step "Step 3: 拷 Python wheels"
mkdir -p /opt/sf/python_wheels
if [[ -d "$BUNDLE_DIR/wheels" ]]; then
    cp -r "$BUNDLE_DIR/wheels/"* /opt/sf/python_wheels/
    ok "Wheels 放在 /opt/sf/python_wheels ($(ls /opt/sf/python_wheels | wc -l) 檔)"
fi

step "Step 4: 跑 install_all.sh"
cd /opt/sf
chmod +x deploy-rhel/*.sh
bash ./deploy-rhel/install_all.sh "$@"
INSTALLEOF

chmod +x "$OUTPUT_DIR/install_offline.sh"
ok "install_offline.sh 寫好"

step "5. 寫 README.md (給 SF 主機端使用者看)"
cat > "$OUTPUT_DIR/README.md" <<MDEOF
# SF File Exchange Server — RHEL 離線安裝包

| 項目 | 值 |
|---|---|
| 打包時間 | $(date) |
| Repo 版本 | $REPO_VER |
| RPM 數 | $RPM_COUNT 個 ($RPM_SIZE) |
| Wheels 數 | $WHL_COUNT 個 ($WHL_SIZE) |
| 打包平台 | $(cat /etc/redhat-release 2>/dev/null) |

## 結構

\`\`\`
sf-rhel-bundle/
├── README.md             ← 本檔
├── install_offline.sh    ← 在 SF 主機跑這個 (一鍵離線安裝)
├── rpms/                 ← 所有 RPM (PostgreSQL / nginx / Samba / Python 等)
├── wheels/               ← Python 套件 (Flask / gunicorn / psycopg2 等)
└── repo/                 ← 整個 cl_ftp source code
\`\`\`

## 在 SF 主機跑 (3 步)

\`\`\`bash
# 1. 解壓
tar xzf sf-rhel-bundle-XXXXX.tar.gz
cd sf-rhel-bundle

# 2. 一鍵離線安裝 (含帳號設定)
sudo SF_ACCOUNTS=u01t SF_PASSWORD='1qaz@WSX' ./install_offline.sh

# 3. 完成後驗證
sudo /opt/sf/deploy-rhel/health_check.sh
\`\`\`

## 對應 Linux 概念

| 步驟 | Linux 對照 |
|---|---|
| install_offline.sh | 像 \`./install.sh\` 一鍵腳本 |
| rpms/*.rpm | yum / dnf 套件 |
| wheels/*.whl | pip 套件 |
| repo/ | git clone 結果 |

## 將來重打包 (有 RHEL 新版時)

在有外網的 PC 跑:
\`\`\`bash
cd /opt/sf
git pull
./deploy-rhel/build_offline_bundle.sh
\`\`\`

MDEOF
ok "README.md 寫好"

step "6. 打包 tar.gz"
cd "$(dirname "$OUTPUT_DIR")"
TARBALL="${BUNDLE_NAME}.tar.gz"
tar czf "$TARBALL" "$(basename "$OUTPUT_DIR")" 2>&1 | tail -3
TARBALL_SIZE=$(du -sh "$TARBALL" | awk '{print $1}')
ok "Tarball: $(pwd)/$TARBALL ($TARBALL_SIZE)"

# 算 SHA256
sha256sum "$TARBALL" > "${TARBALL}.sha256"

step "完成 — Summary"
echo ""
echo "輸出檔:"
echo "  $(pwd)/$TARBALL ($TARBALL_SIZE)"
echo "  $(pwd)/${TARBALL}.sha256"
echo ""
echo "下一步:"
echo "  1. 拷 $TARBALL 到 USB"
echo "  2. USB 到 SF 主機, 解壓:"
echo "       tar xzf $TARBALL"
echo "       cd $(basename "$OUTPUT_DIR")"
echo "  3. 跑離線安裝:"
echo "       sudo SF_ACCOUNTS=u01t SF_PASSWORD='1qaz@WSX' ./install_offline.sh"
echo ""
echo "驗證 SHA256:"
cat "${TARBALL}.sha256"
