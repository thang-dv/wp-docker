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

should_full_sync() {
  if is_truthy "${WP_FORCE_INSTALL:-}"; then
    echo "WP_FORCE_INSTALL is set, running full plugin sync"
    return 0
  fi

  SYNCED=$(wp option get "$PLUGIN_SYNC_OPTION" $FLAGS 2>/dev/null || echo "")
  if [ "$SYNCED" != "1" ]; then
    echo "First plugin sync"
    return 0
  fi

  return 1
}

is_plugin_present() {
  plugin=$1

  if [ -d "$WP_PATH/wp-content/plugins/$plugin" ]; then
    return 0
  fi

  plugin_path=$(wp plugin path "$plugin" $FLAGS 2>/dev/null || true)
  if [ -n "$plugin_path" ] && [ -e "$plugin_path" ]; then
    return 0
  fi

  return 1
}

install_plugin_from_list() {
  plugin=$1
  version=$2
  install_flags=$3

  if [ -z "$version" ] || [ "$version" = "*" ]; then
    echo "Installing $plugin:latest"
    wp plugin install "$plugin" $install_flags || true
  else
    echo "Installing $plugin:$version"
    wp plugin install "$plugin" --version="$version" $install_flags || true
  fi
}

install_plugins_from_file() {
  install_flags=$1

  while IFS=: read plugin version
  do
    plugin=$(printf '%s' "$plugin" | xargs)
    version=$(printf '%s' "$version" | xargs)

    [ -z "$plugin" ] && continue
    case "$plugin" in
      \#*) continue ;;
    esac

    install_plugin_from_list "$plugin" "$version" "$install_flags"
  done < "$PLUGIN_FILE"
}

install_local_plugins() {
  install_flags=$1

  for zip in "$LOCAL_PLUGINS_PATH"/*.zip
  do
    [ -f "$zip" ] || continue
    echo "Installing local plugin $zip"
    wp plugin install "$zip" $install_flags || true
  done
}

remove_unexpected_plugins() {
  EXPECTED=$(grep -v '^#' "$PLUGIN_FILE" | grep -v '^$' | cut -d: -f1 | xargs)
  INSTALLED=$(wp plugin list --field=name $FLAGS)

  for plugin in $INSTALLED
  do
    printf '%s\n' $EXPECTED | grep -qx "$plugin" || {
      echo "Removing plugin $plugin"
      wp plugin delete "$plugin" $FLAGS || true
    }
  done
}

ensure_expected_plugins() {
  missing=0

  while IFS=: read plugin version
  do
    plugin=$(printf '%s' "$plugin" | xargs)
    version=$(printf '%s' "$version" | xargs)

    [ -z "$plugin" ] && continue
    case "$plugin" in
      \#*) continue ;;
    esac

    if is_plugin_present "$plugin"; then
      continue
    fi

    missing=1
    echo "Missing plugin detected: $plugin"
    install_plugin_from_list "$plugin" "$version" "$FLAGS"
  done < "$PLUGIN_FILE"

  for zip in "$LOCAL_PLUGINS_PATH"/*.zip
  do
    [ -f "$zip" ] || continue
    echo "Ensuring local plugin $zip"
    wp plugin install "$zip" $FLAGS || true
    missing=1
  done

  if [ "$missing" -eq 0 ]; then
    echo "All expected plugins are present"
  else
    echo "Missing plugins reinstalled (e.g. after image update)"
  fi
}

echo "Plugin manager start"

if [ ! -f "$PLUGIN_FILE" ]; then
  echo "Plugin file not found, skipping plugin install: $PLUGIN_FILE"
  exit 0
fi

until wp core is-installed $FLAGS 2>/dev/null; do
  sleep 2
done

if should_full_sync; then
  install_plugins_from_file "$FLAGS --force"
  install_local_plugins "$FLAGS --force"
  remove_unexpected_plugins
  wp option update "$PLUGIN_SYNC_OPTION" 1 $FLAGS >/dev/null
  echo "Full plugin sync complete"
else
  ensure_expected_plugins
fi

echo "Plugin manager done"

echo "Plugin repair start"

SITE_URL=$(wp option get siteurl $FLAGS 2>/dev/null)

case "$SITE_URL" in
  *localhost*|*127.0.0.1*)
     echo "Local environment detected"
     wp plugin deactivate better-wp-security $FLAGS || true
     wp plugin deactivate wordfence $FLAGS || true
  ;;
esac

echo "Plugin repair done"
