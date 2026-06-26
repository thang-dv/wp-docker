#!/bin/sh
set -e

WP_PATH=/var/www/html
PLUGIN_FILE=${WP_PLUGINS_FILE:-/docker/config/plugins.txt}
LOCAL_PLUGINS_PATH=${WP_LOCAL_PLUGINS_PATH:-/docker/config/local-plugins}
PLUGIN_SYNC_OPTION=wp_docker_plugins_synced
FLAGS="--path=$WP_PATH --allow-root --skip-plugins --skip-themes"

is_truthy() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

should_sync_plugins() {
  if is_truthy "${WP_FORCE_INSTALL:-}"; then
    echo "WP_FORCE_INSTALL is set, syncing plugins"
    return 0
  fi

  SYNCED=$(wp option get "$PLUGIN_SYNC_OPTION" $FLAGS 2>/dev/null || echo "")
  if [ "$SYNCED" != "1" ]; then
    echo "First plugin sync"
    return 0
  fi

  echo "Plugins already synced, skipping install (set WP_FORCE_INSTALL=1 to reinstall)"
  return 1
}

echo "Plugin manager start"

if [ ! -f "$PLUGIN_FILE" ]; then
  echo "Plugin file not found, skipping plugin install: $PLUGIN_FILE"
  exit 0
fi

until wp core is-installed $FLAGS 2>/dev/null; do
  sleep 2
done

if should_sync_plugins; then
  INSTALL_FLAGS="$FLAGS --force"

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
      wp plugin install "$plugin" $INSTALL_FLAGS || true
    else
      echo "Installing $plugin:$version"
      wp plugin install "$plugin" --version="$version" $INSTALL_FLAGS || true
    fi

  done < "$PLUGIN_FILE"

  # install local plugins
  for zip in "$LOCAL_PLUGINS_PATH"/*.zip
  do
    [ -f "$zip" ] || continue

    echo "Installing local plugin $zip"
    wp plugin install "$zip" $INSTALL_FLAGS || true

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

  wp option update "$PLUGIN_SYNC_OPTION" 1 $FLAGS >/dev/null
  echo "Plugin sync complete"
else
  echo "Plugin sync skipped"
fi

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
