#!/bin/sh
set -e

WP_PATH=/var/www/html

echo "Cache clear start"

until wp core is-installed --path="$WP_PATH" --allow-root 2>/dev/null; do
  sleep 2
done

# wordpress cache
wp cache flush --path="$WP_PATH" --allow-root || true

# redis cache
wp redis flush --path="$WP_PATH" --allow-root 2>/dev/null || true

# transient cache
wp transient delete --all --path="$WP_PATH" --allow-root || true

echo "Cache clear done"