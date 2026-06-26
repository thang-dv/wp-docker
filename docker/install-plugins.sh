#!/bin/sh
set -e

WP_PATH=/var/www/html
PLUGIN_FILE=${WP_PLUGINS_FILE:-/docker/config/plugins.txt}
LOCAL_PLUGINS_PATH=${WP_LOCAL_PLUGINS_PATH:-/docker/config/local-plugins}
FLAGS="--path=$WP_PATH --allow-root --skip-plugins --skip-themes"

echo "Plugin manager start"

if [ ! -f "$PLUGIN_FILE" ]; then
  echo "Plugin file not found, skipping plugin install: $PLUGIN_FILE"
  exit 0
fi

until wp core is-installed $FLAGS 2>/dev/null; do
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
    wp plugin install "$plugin" $FLAGS || true
  else
    echo "Installing $plugin:$version"
    wp plugin install "$plugin" --version="$version" $FLAGS || true
  fi

done < "$PLUGIN_FILE"


# install local plugins
for zip in "$LOCAL_PLUGINS_PATH"/*.zip
do
  [ -f "$zip" ] || continue

  echo "Installing local plugin $zip"
  wp plugin install "$zip" $FLAGS || true

done


# remove plugin ngoài list
EXPECTED=$(grep -v '^#' "$PLUGIN_FILE" | grep -v '^$' | cut -d: -f1 | xargs)

INSTALLED=$(wp plugin list --field=name $FLAGS)

for plugin in $INSTALLED
do
  printf '%s\n' $EXPECTED | grep -qx "$plugin" || {
     echo "Removing plugin $plugin"
     wp plugin delete "$plugin" $FLAGS || true
  }

done

echo "Plugin manager done"

echo "Plugin repair start"

# disable security plugin nếu local
SITE_URL=$(wp option get siteurl $FLAGS 2>/dev/null)

case "$SITE_URL" in
  *localhost*|*127.0.0.1*)
     echo "Local environment detected"
     wp plugin deactivate better-wp-security $FLAGS || true
     wp plugin deactivate wordfence $FLAGS || true
  ;;
esac

echo "Plugin repair done"
