#!/bin/sh
set -e

WP_PATH=/var/www/html
PLUGIN_FILE=${WP_PLUGINS_FILE:-/docker/config/plugins.txt}
LOCAL_PLUGINS_PATH=${WP_LOCAL_PLUGINS_PATH:-/docker/config/local-plugins}

echo "Plugin manager start"

if [ ! -f "$PLUGIN_FILE" ]; then
  echo "Plugin file not found, skipping plugin install: $PLUGIN_FILE"
  exit 0
fi

until wp core is-installed --path="$WP_PATH" --allow-root 2>/dev/null; do
  sleep 2
done

# install/update plugin
while IFS=: read plugin version
do
  plugin=$(printf '%s' "$plugin" | xargs)
  version=$(printf '%s' "$version" | xargs)

  [ -z "$plugin" ] && continue
  case "$plugin" in
    \#*) continue ;;
  esac

  if [ -z "$version" ] || [ "$version" = "*" ]; then
    echo "Installing $plugin:latest"

    wp plugin install "$plugin" \
       --path="$WP_PATH" \
       --allow-root \
       --skip-plugins \
       || true
  else
    echo "Installing $plugin:$version"

    wp plugin install "$plugin" \
       --version="$version" \
       --path="$WP_PATH" \
       --allow-root \
       --skip-plugins \
       || true
  fi

done < "$PLUGIN_FILE"


# install local plugins
for zip in "$LOCAL_PLUGINS_PATH"/*.zip
do
  [ -f "$zip" ] || continue

  echo "Installing local plugin $zip"

  wp plugin install "$zip" \
     --path="$WP_PATH" \
     --allow-root \
     --skip-plugins \
     || true

done


# remove plugin ngoài list
EXPECTED=$(cut -d: -f1 "$PLUGIN_FILE")

INSTALLED=$(wp plugin list --field=name --path="$WP_PATH" --allow-root)

for plugin in $INSTALLED
do
  echo "$EXPECTED" | grep -qx "$plugin" || {

     echo "Removing plugin $plugin"

     wp plugin delete "$plugin" \
       --path="$WP_PATH" \
       --allow-root \
       --skip-plugins \
       || true
  }

done

echo "Plugin manager done"

echo "Plugin repair start"

# disable security plugin nếu local
SITE_URL=$(wp option get siteurl --path="$WP_PATH" --allow-root 2>/dev/null)

case "$SITE_URL" in
  *localhost*|*127.0.0.1*)
     echo "Local environment detected"

     wp plugin deactivate better-wp-security --allow-root --skip-plugins || true
     wp plugin deactivate wordfence --allow-root --skip-plugins || true
  ;;
esac

echo "Plugin repair done"
