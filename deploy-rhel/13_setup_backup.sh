#!/bin/bash
# 設定備份 (rsync + cron)
set -euo pipefail
PORTAL="${SF_PORTAL_ROOT:-/opt/portal}"
DATA="${SF_DATA_ROOT:-/data/exchange}"
BACKUP_TARGET="${SF_BACKUP_TARGET:-/backup/sf}"

echo "=== 設定備份 ==="

mkdir -p "$BACKUP_TARGET" "$PORTAL/scripts"

cat > "$PORTAL/scripts/run_daily_backup.sh" <<EOF
#!/bin/bash
# SF Daily Backup
set -euo pipefail
DATE=\$(date +%Y%m%d_%H%M%S)
TARGET="$BACKUP_TARGET/sf_\${DATE}"

# 業務檔 (rsync, hard-link 增量)
rsync -a --link-dest="$BACKUP_TARGET/latest" "$DATA/" "\$TARGET/data/" 2>/dev/null

# Portal app + config
rsync -a "$PORTAL/app/" "\$TARGET/portal/"

# DB (pg_dump)
sudo -u postgres pg_dump file_exchange_audit | gzip > "\$TARGET/db.sql.gz"

# 配置檔
mkdir -p "\$TARGET/etc"
cp /etc/ssh/sshd_config /etc/nginx/conf.d/sf-portal.conf /etc/samba/smb.conf "\$TARGET/etc/" 2>/dev/null || true

# 更新 latest symlink
ln -sfn "\$TARGET" "$BACKUP_TARGET/latest"

# 保留 30 天
find "$BACKUP_TARGET" -maxdepth 1 -type d -name 'sf_*' -mtime +30 -exec rm -rf {} \;

echo "[ok] Backup: \$TARGET"
EOF
chmod +x "$PORTAL/scripts/run_daily_backup.sh"

# 排程 (cron, 每天 1 AM)
cat > /etc/cron.d/sf-daily-backup <<EOF
0 1 * * * root $PORTAL/scripts/run_daily_backup.sh >> /var/log/sf-portal/backup.log 2>&1
EOF
echo "[ok] cron 排程: /etc/cron.d/sf-daily-backup"

echo "  測試: sudo $PORTAL/scripts/run_daily_backup.sh"
