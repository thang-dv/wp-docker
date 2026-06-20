#!/bin/sh

WP_PATH=/var/www/html

# đợi core tồn tại
while [ ! -f "$WP_PATH/wp-settings.php" ]; do
  sleep 3
done

echo "WP-CLI cron started..."

while true; do
  wp cron event run --due-now \
    --path="$WP_PATH" \
    --allow-root || true

  sleep 60
done