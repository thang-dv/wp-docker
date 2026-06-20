#!/bin/sh
WP_PATH=/var/www/html

[ ! -f "$WP_PATH/wp-settings.php" ] && exit 0

wp cron event run --due-now \
  --path="$WP_PATH" \
  --skip-plugins \
  --skip-themes \
  --allow-root