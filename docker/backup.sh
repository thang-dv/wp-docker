#!/bin/sh
set -e

WP_PATH=/var/www/html
BACKUP_DIR=${WP_BACKUP_DIR:-/docker/backups}
FLAGS="--path=$WP_PATH --allow-root --skip-plugins --skip-themes"
TIMESTAMP=$(date -u +%Y%m%d-%H%M%S)
ARCHIVE_NAME="wp-backup-${TIMESTAMP}.tar.gz"
STAGING_NAME="wp-backup-${TIMESTAMP}"

mkdir -p "$BACKUP_DIR"

echo "Backup start"

until wp core is-installed $FLAGS 2>/dev/null; do
  echo "Waiting for WordPress..."
  sleep 2
done

WORKDIR=$(mktemp -d)
STAGING="$WORKDIR/$STAGING_NAME"
mkdir -p "$STAGING/wp-content"

echo "Exporting database..."
wp db export "$STAGING/database.sql" $FLAGS

for dir in themes uploads mu-plugins plugins; do
  if [ -d "$WP_PATH/wp-content/$dir" ]; then
    echo "Archiving wp-content/$dir..."
    cp -a "$WP_PATH/wp-content/$dir" "$STAGING/wp-content/"
  fi
done

{
  echo "timestamp=$TIMESTAMP"
  echo "siteurl=$(wp option get siteurl $FLAGS 2>/dev/null || echo unknown)"
  echo "home=$(wp option get home $FLAGS 2>/dev/null || echo unknown)"
  wp core version $FLAGS 2>/dev/null || true
} > "$STAGING/manifest.txt"

tar -czf "$BACKUP_DIR/$ARCHIVE_NAME" -C "$WORKDIR" "$STAGING_NAME"
rm -rf "$WORKDIR"

echo "Backup saved: $BACKUP_DIR/$ARCHIVE_NAME"

if [ -n "${WP_BACKUP_KEEP:-}" ]; then
  KEEP=$WP_BACKUP_KEEP
  count=0
  for backup in $(ls -1t "$BACKUP_DIR"/wp-backup-*.tar.gz 2>/dev/null); do
    count=$((count + 1))
    if [ "$count" -gt "$KEEP" ]; then
      echo "Removing old backup: $backup"
      rm -f "$backup"
    fi
  done
fi

echo "Backup done"
