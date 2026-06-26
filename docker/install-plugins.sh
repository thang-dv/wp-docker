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

plugin_slug_from_zip() {
  basename "$1" .zip
}

is_plugin_dir_valid() {
  dir=$1
  [ -d "$dir" ] || return 1
  find "$dir" -maxdepth 2 -name '*.php' 2>/dev/null | head -1 | grep -q .
}

is_plugin_present() {
  plugin=$1

  if is_plugin_dir_valid "$WP_PATH/wp-content/plugins/$plugin"; then
    return 0
  fi

  plugin_path=$(wp plugin path "$plugin" $FLAGS 2>/dev/null || true)
  if [ -n "$plugin_path" ] && [ -e "$plugin_path" ]; then
    return 0
  fi

  return 1
}

is_local_zip_installed() {
  zip=$1
  slug=$(plugin_slug_from_zip "$zip")
  is_plugin_dir_valid "$WP_PATH/wp-content/plugins/$slug"
}

expected_plugin_slugs() {
  if [ -f "$PLUGIN_FILE" ]; then
    grep -v '^#' "$PLUGIN_FILE" | grep -v '^$' | cut -d: -f1 | xargs
  fi

  for zip in "$LOCAL_PLUGINS_PATH"/*.zip
  do
    [ -f "$zip" ] || continue
    plugin_slug_from_zip "$zip"
  done
}

install_plugin_from_list() {
  plugin=$1
  version=$2
  install_flags=$3

  if is_truthy "${WP_FORCE_INSTALL:-}"; then
    :
  elif is_plugin_present "$plugin"; then
    echo "Plugin already installed: $plugin"
    return 0
  fi

  target="$WP_PATH/wp-content/plugins/$plugin"
  if [ -d "$target" ] && ! is_plugin_dir_valid "$target"; then
    echo "Removing incomplete plugin folder: $plugin"
    rm -rf "$target"
  fi

  if [ -z "$version" ] || [ "$version" = "*" ]; then
    echo "Installing $plugin:latest"
    wp plugin install "$plugin" $install_flags || true
  else
    echo "Installing $plugin:$version"
    wp plugin install "$plugin" --version="$version" $install_flags || true
  fi
}

install_local_zip() {
  zip=$1
  install_flags=$2
  slug=$(plugin_slug_from_zip "$zip")
  target="$WP_PATH/wp-content/plugins/$slug"

  if [ ! -f "$zip" ]; then
    echo "Local plugin zip not found: $zip"
    return 1
  fi

  if ! is_truthy "${WP_FORCE_INSTALL:-}" && is_local_zip_installed "$zip"; then
    echo "Local plugin already installed: $slug"
    return 0
  fi

  if [ -d "$target" ]; then
    echo "Removing existing plugin folder before zip install: $slug"
    rm -rf "$target"
  fi

  echo "Installing local plugin $zip"
  wp plugin install "$zip" $install_flags --force || true
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

    # Skip wp.org install when a local zip provides the same slug (e.g. ACF Pro)
    if [ -f "$LOCAL_PLUGINS_PATH/$plugin.zip" ]; then
      echo "Skipping wp.org install for $plugin (local zip available)"
      continue
    fi

    install_plugin_from_list "$plugin" "$version" "$install_flags"
  done < "$PLUGIN_FILE"
}

install_local_plugins() {
  install_flags=$1

  for zip in "$LOCAL_PLUGINS_PATH"/*.zip
  do
    [ -f "$zip" ] || continue
    install_local_zip "$zip" "$install_flags"
  done
}

remove_unexpected_plugins() {
  EXPECTED=$(expected_plugin_slugs)
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

    if [ -f "$LOCAL_PLUGINS_PATH/$plugin.zip" ]; then
      continue
    fi

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

    if is_local_zip_installed "$zip"; then
      continue
    fi

    missing=1
    install_local_zip "$zip" "$FLAGS"
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
elif [ -z "$(ls -A "$WP_PATH/wp-content/plugins" 2>/dev/null)" ]; then
  echo "Plugins directory empty, installing missing plugins"
  ensure_expected_plugins
  wp option update "$PLUGIN_SYNC_OPTION" 1 $FLAGS >/dev/null
else
  echo "Plugin sync skipped (set WP_FORCE_INSTALL=1 or run sync-plugins.sh to resync)"
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
