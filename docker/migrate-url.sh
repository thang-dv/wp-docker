#!/bin/sh
set -e

WP_PATH=/var/www/html
FLAG=_env_url_migrated

echo "Waiting WordPress..."

# chờ wp-config
while [ ! -f "$WP_PATH/wp-config.php" ]; do
  sleep 2
done

# chờ DB + WP install
until wp core is-installed --path="$WP_PATH" --allow-root 2>/dev/null; do
  sleep 2
done

CURRENT=$(wp option get siteurl \
  --path="$WP_PATH" \
  --skip-plugins \
  --skip-themes \
  --allow-root)

MIGRATED=$(wp option get "$FLAG" \
  --path="$WP_PATH" \
  --allow-root 2>/dev/null || true)

[ "$MIGRATED" = "1" ] && exit 0

echo "Current URL: $CURRENT"
echo "Target URL:  $WP_SITEURL"

if [ "$CURRENT" != "$WP_SITEURL" ]; then

  echo "Updating siteurl + home..."
  wp option update siteurl "$WP_SITEURL" --path="$WP_PATH" --allow-root
  wp option update home "$WP_SITEURL" --path="$WP_PATH" --allow-root

  echo "Running search-replace..."
  wp search-replace "$CURRENT" "$WP_SITEURL" \
    --all-tables \
    --precise \
    --skip-columns=guid \
    --skip-plugins \
    --skip-themes \
    --allow-root

  echo "Updating Elementor URLs..."
  wp elementor replace-urls "$CURRENT" "$WP_SITEURL" \
    --path="$WP_PATH" \
    --allow-root || true

  echo "Regenerating Elementor CSS..."
  wp elementor flush-css \
    --path="$WP_PATH" \
    --allow-root || true

fi

wp option update "$FLAG" 1 --path="$WP_PATH" --allow-root

echo "Migration done"