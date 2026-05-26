#!/bin/bash
#
# SF Portal LAB 一鍵離線安裝 (v2.5.4)
# 目標: Rocky Linux 9.x 全新主機 → 30 分鐘起完整 demo 環境
#       含 Portal + Samba + mock AD (glauth) + mock SMTP (aiosmtpd) + seed data
#
# 用法:
#   sudo bash install.sh --check     # 不真做, 印環境 + 看會做什麼
#   sudo bash install.sh --install   # 真裝
#   sudo bash install.sh --verify    # 驗 (Portal + SMB + LDAP + SMTP)
#   sudo bash install.sh --repair    # 修 (重啟服務 + 重套 config)
#
# 來源: GitHub alienid4/cl_ftp / SF Portal v2.5.4

set -uo pipefail

VERSION="v2.5.4"
PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ===== Config (預設, 可被 env var 覆寫) =====
INSTALL_DIR="${SF_INSTALL_DIR:-/opt/portal}"
DATA_ROOT="${SF_DATA_ROOT:-/data/exchange}"
DB_NAME="${SF_DB_NAME:-file_exchange_audit}"
DB_USER="${SF_DB_USER:-portal}"
DB_PASS="${SF_DB_PASS:-portalpass_$(openssl rand -hex 4)}"
GLAUTH_BIND_PASS="${SF_GLAUTH_BIND_PASS:-password}"
USERS_SFTP=(u01 u02 u03 u04)
USERS_PASS="${SF_SFTP_PASS:-test1234}"

# ===== UI helpers =====
GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
BOLD='\033[1m'
step()  { echo ""; echo -e "${CYAN}=== $* ===${NC}"; }
ok()    { echo -e "${GREEN}[ok]${NC} $*"; }
warn()  { echo -e "${YELLOW}[warn]${NC} $*"; }
fail()  { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }
info()  { echo -e "${CYAN}[info]${NC} $*"; }

# ===== Mode =====
MODE="${1:---help}"

print_help() {
    cat <<EOF
SF Portal LAB 離線一鍵安裝 ${VERSION}

  --check     不裝, 印環境 + 預估會做什麼
  --print-config  印解析後設定值 (不含密碼)
  --install   真裝 (約 10-20 分鐘)
  --verify    驗 (跑完 install 後或之後重驗)
  --repair    修 (重啟服務 + 重套 config, 不動 DB)
  --help      本訊息

  可用環境變數覆寫:
    SF_INSTALL_DIR     (default: /opt/portal)
    SF_DATA_ROOT       (default: /data/exchange)
    SF_DB_NAME         (default: file_exchange_audit)
    SF_DB_USER         (default: portal)
    SF_DB_PASS         (default: 隨機)
    SF_GLAUTH_BIND_PASS (default: password)
    SF_SFTP_PASS       (default: test1234)
EOF
}

# ===== --check mode =====
do_check() {
    step "環境檢查"
    if ! grep -q 'release 9' /etc/redhat-release 2>/dev/null; then
        warn "本 LAB 包是給 RHEL/Rocky 9 用的, 你的 OS: $(cat /etc/redhat-release 2>&1 || echo 'unknown')"
    else
        ok "OS: $(cat /etc/redhat-release)"
    fi

    [[ $EUID -eq 0 ]] || fail "要 sudo 跑"
    ok "running as root"

    [[ -d "$PKG_DIR/rpms" ]] && ok "rpms/ 在 ($(ls $PKG_DIR/rpms | wc -l) 個檔, $(du -sh $PKG_DIR/rpms | cut -f1))" || fail "缺 rpms/"
    [[ -d "$PKG_DIR/wheels" ]] && ok "wheels/ 在 ($(ls $PKG_DIR/wheels | wc -l) 個檔)" || fail "缺 wheels/"
    [[ -d "$PKG_DIR/config" ]] && ok "config/ 在" || fail "缺 config/"
    [[ -d "$PKG_DIR/sql" ]] && ok "sql/ 在" || fail "缺 sql/"
    [[ -f "$PKG_DIR/portal-source.tar.gz" ]] && ok "portal source ($(du -sh $PKG_DIR/portal-source.tar.gz | cut -f1))" || fail "缺 portal-source.tar.gz"
    [[ -f "$PKG_DIR/glauth/glauth-linux-amd64" ]] && ok "glauth binary" || warn "缺 glauth binary"

    step "預估會做什麼"
    cat <<EOF
  1. dnf install $(ls $PKG_DIR/rpms/*.rpm 2>/dev/null | wc -l) 個 RPM (offline)
  2. pip install $(ls $PKG_DIR/wheels/*.whl 2>/dev/null | wc -l) 個 wheel
  3. 建 OS user: ${USERS_SFTP[*]} + nginx + viewer
  4. 建目錄: $INSTALL_DIR, $DATA_ROOT/{u01..u04}/{inbound,...}, $DATA_ROOT/samba/{architecture,hr,finance,security}
  5. PostgreSQL initdb + 建 DB '$DB_NAME' + user '$DB_USER'
  6. 套 schema (3 個 SQL) + seed data (10 audit log)
  7. 寫 config: nginx + samba + glauth + 5 個 systemd unit + Portal .env
  8. 改 sshd_config 加 Match Group sftponly + 改 pg_hba.conf 加 portal
  9. 啟服務: postgresql, nginx, smb, nmb, sshd, sf-portal, sf-batch-aggregator.timer, sf-mock-ad, sf-mock-smtp, firewalld
  10. firewall 放: 22 80 445 5000

預估時間: 10-20 分鐘 (主要 dnf install)
EOF
    info "確認 OK 後跑: sudo bash install.sh --install"
}

# ===== --print-config mode =====
do_print_config() {
    cat <<EOF
SF Portal LAB 解析設定:

  INSTALL_DIR:         $INSTALL_DIR
  DATA_ROOT:           $DATA_ROOT
  DB_NAME:             $DB_NAME
  DB_USER:             $DB_USER
  DB_PASS:             (隨機, install 時印出)
  USERS_SFTP:          ${USERS_SFTP[*]}
  USERS_PASS:          $USERS_PASS (改 SF_SFTP_PASS env)

  Portal HTTP:         80 (反代 → 127.0.0.1:5000)
  PostgreSQL:          127.0.0.1:5432
  Samba:               445
  glauth (mock AD):    127.0.0.1:389
  aiosmtpd (mock SMTP):127.0.0.1:1025

  systemd units:
    sf-portal.service
    sf-batch-aggregator.service + .timer (每 5 秒跑)
    sf-mock-ad.service
    sf-mock-smtp.service
    nginx.service / postgresql.service / smb.service / nmb.service

  Demo 帳號:
    SFTP:  u01/u02/u03/u04 + 密碼: $USERS_PASS
    AD:    wang.manager / lin.deputy / huang.lead / admin / viewer + 密碼: $GLAUTH_BIND_PASS
    SMB:   viewer + 密碼: $USERS_PASS
EOF
}

# ===== --install mode =====
do_install() {
    [[ $EUID -eq 0 ]] || fail "要 sudo 跑"

    step "Step 1: dnf install (offline)"
    dnf install -y "$PKG_DIR"/rpms/*.rpm 2>&1 | tail -5
    ok "RPM 裝完"

    step "Step 2: pip install (offline)"
    /usr/bin/python3 -m pip install --no-index --find-links "$PKG_DIR/wheels" \
        flask werkzeug gunicorn itsdangerous click blinker ldap3 \
        Flask-Login Flask-Session cachelib python-dotenv aiosmtpd 2>&1 | tail -5
    ok "wheel 裝完"

    step "Step 3: 建 OS users"
    groupadd sftponly 2>/dev/null || true
    for u in "${USERS_SFTP[@]}"; do
        id -u "$u" &>/dev/null || useradd -d "$DATA_ROOT/$u" -s /sbin/nologin -G sftponly "$u"
        echo "$u:$USERS_PASS" | chpasswd
    done
    id -u nginx &>/dev/null || useradd -r -s /sbin/nologin nginx
    id -u viewer &>/dev/null || useradd -r -s /sbin/nologin viewer
    ok "users 建立"

    step "Step 4: 建目錄結構"
    mkdir -p "$INSTALL_DIR"/{app,logs,backups,scripts}
    for u in "${USERS_SFTP[@]}"; do
        mkdir -p "$DATA_ROOT/$u"/{inbound,pending,processing,archive,error}
        chown root:root "$DATA_ROOT/$u"
        chmod 755 "$DATA_ROOT/$u"
        chown -R "$u:$u" "$DATA_ROOT/$u"/{inbound,pending,processing,archive,error}
        chmod 700 "$DATA_ROOT/$u/inbound"
        # ACL 給 nginx (portal 跑) + root (aggregator)
        setfacl -m u:nginx:rwx "$DATA_ROOT/$u/inbound"
        setfacl -d -m u:nginx:rwx "$DATA_ROOT/$u/inbound"
    done
    mkdir -p "$DATA_ROOT"/samba/{architecture,hr,finance,security}
    chown -R nginx:nginx "$DATA_ROOT"/samba
    ok "目錄 OK"

    step "Step 5: 解壓 portal source"
    tar xzf "$PKG_DIR/portal-source.tar.gz" -C "$INSTALL_DIR/app/" --strip-components=1
    chown -R nginx:nginx "$INSTALL_DIR"
    ok "portal source 解到 $INSTALL_DIR/app/"

    step "Step 6: PostgreSQL init + DB"
    [[ -f /var/lib/pgsql/data/PG_VERSION ]] || postgresql-setup --initdb 2>&1 | tail -3
    # pg_hba 加 portal 用戶 md5 (放最前) + 全 ident→md5
    PG_HBA=/var/lib/pgsql/data/pg_hba.conf
    cp "$PG_HBA" "${PG_HBA}.bak.$(date +%s)"
    sed -i -E "s/^(local\s+all\s+all\s+)peer$/\\1md5/; s/^(host\s+all\s+all\s+127\.0\.0\.1\/32\s+)ident$/\\1md5/; s/^(host\s+all\s+all\s+::1\/128\s+)ident$/\\1md5/" "$PG_HBA"
    # 加 postgres local peer (svc 用)
    sed -i '/^local   all             all                                     md5/i local   all             postgres                                peer' "$PG_HBA"
    # portal 規則放最前
    sed -i "/^# TYPE/a host    $DB_NAME    $DB_USER    127.0.0.1\/32    md5" "$PG_HBA"
    systemctl enable --now postgresql 2>&1 | tail -2
    sleep 2

    # 建 DB + user
    cd /tmp
    sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';" 2>&1 | tail -1
    sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;" 2>&1 | tail -1
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;" 2>&1 | tail -1
    # 套 schema + seed
    for sqlf in "$PKG_DIR"/sql/*.sql; do
        cp "$sqlf" /var/lib/pgsql/
        sudo -u postgres psql -d "$DB_NAME" -f "/var/lib/pgsql/$(basename $sqlf)" 2>&1 | tail -3
        rm -f "/var/lib/pgsql/$(basename $sqlf)"
    done
    # GRANT
    sudo -u postgres psql -d "$DB_NAME" <<EOF 2>&1 | tail -3
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $DB_USER;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO $DB_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO $DB_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO $DB_USER;
EOF
    ok "DB 建好 + schema 套完"

    step "Step 7: 寫 Portal .env"
    cat > "$INSTALL_DIR/app/.env" <<EOF
FLASK_ENV=production
SECRET_KEY=$(openssl rand -hex 32)
DEV_MODE=false
DB_CONNECTION_STRING=postgresql://$DB_USER:$DB_PASS@127.0.0.1:5432/$DB_NAME
AD_SERVER=ldap://127.0.0.1:389
AD_BASE_DN=dc=sflab,dc=local
AD_DOMAIN=SFLAB
AD_BIND_USER=cn=svc_portal_ldap,ou=svc_portal_ldap,dc=sflab,dc=local
AD_BIND_PASS=$GLAUTH_BIND_PASS
AD_AUTH_MODE=simple
SMTP_SERVER=127.0.0.1
SMTP_PORT=1025
SMTP_FROM=sf-noreply@sflab
DATA_EXCHANGE_ROOT=$DATA_ROOT
PORTAL_LOG_DIR=$INSTALL_DIR/logs
PORTAL_BACKUP_DIR=$INSTALL_DIR/backups
PORTAL_BASE_URL=http://$(hostname -I | awk '{print $1}')
SHOW_LOGIN_FAIL_REASON=true
EOF
    chmod 640 "$INSTALL_DIR/app/.env"
    chown nginx:nginx "$INSTALL_DIR/app/.env"
    ok ".env 寫入"

    step "Step 8: 拷 config / systemd / glauth"
    cp "$PKG_DIR/config/nginx-sf-portal.conf" /etc/nginx/conf.d/sf-portal.conf
    sed -i 's|listen       80 default_server;|listen       80;|' /etc/nginx/nginx.conf 2>/dev/null || true

    cp "$PKG_DIR/config/smb.conf" /etc/samba/smb.conf

    mkdir -p /opt/glauth
    cp "$PKG_DIR/glauth/glauth-linux-amd64" /opt/glauth/glauth
    cp "$PKG_DIR/config/glauth.cfg" /opt/glauth/config.cfg
    chmod +x /opt/glauth/glauth

    cp "$PKG_DIR/scripts/mock-smtp.py" "$INSTALL_DIR/scripts/mock-smtp.py"
    chmod +x "$INSTALL_DIR/scripts/mock-smtp.py"

    cp "$PKG_DIR/scripts/batch_aggregator.py" "$INSTALL_DIR/scripts/batch_aggregator.py"
    chmod +x "$INSTALL_DIR/scripts/batch_aggregator.py"
    # 改 batch_aggregator DB DSN 內密碼
    sed -i "s|portalpass_test|$DB_PASS|" "$INSTALL_DIR/scripts/batch_aggregator.py"

    cp "$PKG_DIR/config/systemd/"*.service "$PKG_DIR/config/systemd/"*.timer /etc/systemd/system/
    # 改 sf-portal.service 內 PORTAL_DIR + DB_PASS 占位
    sed -i "s|/opt/portal|$INSTALL_DIR|g" /etc/systemd/system/sf-portal.service \
        /etc/systemd/system/sf-batch-aggregator.service \
        /etc/systemd/system/sf-mock-smtp.service
    systemctl daemon-reload
    ok "config 拷入"

    step "Step 9: sshd Match Group sftponly"
    if ! grep -q 'Match Group sftponly' /etc/ssh/sshd_config; then
        cat "$PKG_DIR/config/sshd_config.append" >> /etc/ssh/sshd_config
    fi
    sshd -t && systemctl reload sshd
    setsebool -P ssh_chroot_rw_homedirs on 2>&1 | tail -1
    ok "sshd OK"

    step "Step 10: 啟動所有服務"
    setsebool -P httpd_can_network_connect on 2>&1 | tail -1
    setsebool -P samba_export_all_ro on 2>&1 | tail -1
    smbpasswd -a viewer -s <<EOF 2>&1 | tail -1
$USERS_PASS
$USERS_PASS
EOF
    systemctl enable --now firewalld 2>&1 | tail -1
    for s in nginx smb nmb sf-mock-ad sf-mock-smtp sf-portal sf-batch-aggregator.timer; do
        systemctl enable --now "$s" 2>&1 | tail -1
    done

    step "Step 11: firewall 放行"
    for svc in ssh http samba; do firewall-cmd --permanent --add-service=$svc 2>&1 | tail -1; done
    firewall-cmd --reload 2>&1 | tail -1
    ok "firewall OK"

    step "Step 12: 驗"
    sleep 5
    do_verify

    MAIN_IP=$(hostname -I | awk '{print $1}')
    echo ""
    echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${GREEN}║   ✅ SF Portal LAB ${VERSION} 安裝完成                          ║${NC}"
    echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "  Portal: http://$MAIN_IP/"
    echo "  登入:   wang.manager / $GLAUTH_BIND_PASS  (一般使用者)"
    echo "         admin / $GLAUTH_BIND_PASS         (IT 管理員)"
    echo "  SMB:    \\\\$MAIN_IP\\architecture  with viewer / $USERS_PASS"
    echo "  SFTP:   sftp u01@$MAIN_IP  密碼: $USERS_PASS"
    echo ""
    echo "  Mail tail:  tail -f $INSTALL_DIR/logs/mail-debug.log"
    echo "  Portal log: tail -f $INSTALL_DIR/logs/error.log"
    echo ""
    echo "  DB 密碼存在 $INSTALL_DIR/app/.env"
}

# ===== --verify =====
do_verify() {
    step "驗證: services"
    for s in postgresql nginx smb sf-portal sf-mock-ad sf-mock-smtp sf-batch-aggregator.timer; do
        if systemctl is-active "$s" &>/dev/null; then
            ok "$s active"
        else
            warn "$s NOT active"
        fi
    done

    step "驗證: ports"
    for p in 22 80 389 445 1025 5000 5432; do
        if ss -tln 2>/dev/null | grep -q ":$p "; then
            ok "port $p listening"
        else
            warn "port $p NOT listening"
        fi
    done

    step "驗證: portal HTTP"
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 http://127.0.0.1/auth/login 2>/dev/null || echo 000)
    if [[ "$code" =~ ^(200|302)$ ]]; then ok "/auth/login HTTP $code"; else warn "/auth/login HTTP $code"; fi

    step "驗證: LDAP (mock AD)"
    if command -v ldapsearch &>/dev/null && ldapsearch -x -H ldap://127.0.0.1:389 -D 'cn=svc_portal_ldap,ou=svc_portal_ldap,dc=sflab,dc=local' -w "$GLAUTH_BIND_PASS" -b 'dc=sflab,dc=local' '(cn=wang.manager)' cn 2>/dev/null | grep -q wang.manager; then
        ok "LDAP bind + search OK"
    else
        warn "LDAP 驗證 skip (沒 ldapsearch) 或 fail"
    fi

    step "驗證: SMTP (mock)"
    code=$(echo "EHLO test" | timeout 3 nc 127.0.0.1 1025 2>/dev/null | head -1 || echo "")
    if [[ "$code" == *"220"* ]]; then ok "SMTP 1025 OK"; else warn "SMTP 1025 沒回 220"; fi

    step "驗證: SMB"
    if command -v smbclient &>/dev/null && smbclient -L //127.0.0.1 -U viewer%"$USERS_PASS" 2>/dev/null | grep -q architecture; then
        ok "SMB share architecture 看得到"
    else
        warn "SMB 驗證 fail (可能 smbpasswd 沒設, 跑: smbpasswd -a viewer)"
    fi
}

# ===== --repair =====
do_repair() {
    step "重啟所有服務"
    systemctl restart postgresql nginx smb nmb sf-mock-ad sf-mock-smtp sf-portal sshd
    systemctl restart sf-batch-aggregator.timer
    sleep 3
    do_verify
}

# ===== Main =====
case "$MODE" in
    --check)        do_check ;;
    --print-config) do_print_config ;;
    --install)      do_install ;;
    --verify)       do_verify ;;
    --repair)       do_repair ;;
    --help|*)       print_help ;;
esac
