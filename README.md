# Reusable WordPress Docker Image

This repository builds a reusable WordPress Docker image for other WP projects.

The image includes:

- Configurable WordPress base image via `WORDPRESS_IMAGE`
- WP-CLI
- Supervisor for WP cron
- URL migration script based on `WP_SITEURL`
- Cache clearing script
- Backup script for database and `wp-content` (themes, uploads, mu-plugins, plugins)
- Plugin installer from `plugins.txt` and `.zip` files in `local-plugins/` (if present)
- Custom `php.ini` when mounted via config

## Image on GHCR

The image is **public** — pull without login. Supports `linux/amd64` and `linux/arm64` (no `platform: linux/amd64` needed on Apple Silicon):

```sh
docker pull ghcr.io/thang-dv/wp-docker:latest
```

Default image:

```txt
ghcr.io/thang-dv/wp-docker:latest
```

The workflow also publishes tags by branch, git tag, and SHA. Examples:

```txt
ghcr.io/thang-dv/wp-docker:dev
ghcr.io/thang-dv/wp-docker:main
ghcr.io/thang-dv/wp-docker:v1.0.0
ghcr.io/thang-dv/wp-docker:sha-<commit>
```

On first publish, org GHCR packages default to **private**. The workflow sets visibility to **public** after push. If the API lacks permission, set it manually under **Package settings → Change visibility → Public**:

`https://github.com/orgs/thang-dv/packages/container/wp-docker/settings`

## Local Build

```sh
docker build \
  --build-arg WORDPRESS_IMAGE=wordpress:php8.4-apache \
  -t reusable-wordpress:php8.4-apache \
  ./docker
```

`docker-compose.yaml` in this repo is a reference for consuming the image, not a full stack. The database should live in your real WP project or an external service.

## Use in Another WP Project

In your WordPress project, use the GHCR image and configure options in `.env`:

```yaml
services:
  wordpress:
    image: ghcr.io/thang-dv/wp-docker:latest
    container_name: wordpress
    restart: unless-stopped
    ports:
      - "${WP_BIND_HOST:-127.0.0.1}:${WP_PORT:-8084}:80"
    environment:
      WORDPRESS_DB_HOST: "${DB_HOST}"
      WORDPRESS_DB_NAME: "${DB_NAME}"
      WORDPRESS_DB_USER: "${DB_USER}"
      WORDPRESS_DB_PASSWORD: "${DB_PASSWORD}"
      WP_SITEURL: "${WP_SITEURL}"
      WP_HOME: "${WP_HOME}"
      WP_FORCE_INSTALL: "${WP_FORCE_INSTALL:-}"
      WP_DEBUG: ${WP_DEBUG:-false}
      WORDPRESS_CONFIG_EXTRA: |
        define('WP_HOME', '${WP_HOME}');
        define('WP_SITEURL', '${WP_SITEURL}');
        define('WP_DEBUG', ${WP_DEBUG:-false});
        define('WP_DEBUG_LOG', ${WORDPRESS_DEBUG_LOG:-false});
        define('WP_DEBUG_DISPLAY', ${WORDPRESS_DEBUG_DISPLAY:-false});
        define('DISABLE_WP_CRON', ${WORDPRESS_DISABLE_CRON:-false});
    volumes:
      - ${WP_CONTENT_PATH:-./wp-content}/themes:/var/www/html/wp-content/themes
      - ${WP_CONTENT_PATH:-./wp-content}/uploads:/var/www/html/wp-content/uploads
      - ${WP_CONTENT_PATH:-./wp-content}/mu-plugins:/var/www/html/wp-content/mu-plugins
      - ${WP_BACKUP_PATH:-./backups}:/docker/backups
      - ${WP_CONFIG_PATH:-./docker-config}:/docker/config:ro
```

Only persistent `wp-content` subdirectories are mounted:

| Mount | Host path | Purpose |
|-------|-----------|---------|
| Themes | `./wp-content/themes` | Custom themes |
| Uploads | `./wp-content/uploads` | Media library |
| MU-plugins | `./wp-content/mu-plugins` | Must-use plugins (e.g. custom shortcodes) |

`wp-content/plugins` is **not** mounted. Plugins live in the container and are managed by `install-plugins.sh` from `plugins.txt`. Rebuild or set `WP_FORCE_INSTALL=1` to resync.

Create host directories before first run if needed:

```sh
mkdir -p wp-content/{themes,uploads,mu-plugins}
```

Example `.env`:

```env
WP_BIND_HOST=127.0.0.1
WP_PORT=8084
WP_SITEURL=http://localhost:8084
WP_HOME=http://localhost:8084
WP_CONTENT_PATH=./wp-content
WP_BACKUP_PATH=./backups
WP_BACKUP_KEEP=5
WP_CONFIG_PATH=./docker-config
PHP_INI_FILE=/docker/config/php.ini
WP_PLUGINS_FILE=/docker/config/plugins.txt
WP_LOCAL_PLUGINS_PATH=/docker/config/local-plugins
WP_FORCE_INSTALL=
WP_HEALTHCHECK_URL=http://localhost/wp-login.php
WP_HEALTHCHECK_INTERVAL=15s
WP_HEALTHCHECK_TIMEOUT=5s
WP_HEALTHCHECK_RETRIES=5
WP_HEALTHCHECK_START_PERIOD=30s

DB_HOST=mariadb:3306
DB_NAME=wp_docker
DB_USER=root
DB_PASSWORD=root

WP_DEBUG=true
WORDPRESS_DEBUG_LOG=false
WORDPRESS_DEBUG_DISPLAY=false
WORDPRESS_DISABLE_CRON=true
```

To pin a stable version, use a release tag or SHA instead of `latest`:

```yaml
services:
  wordpress:
    image: ghcr.io/thang-dv/wp-docker:v1.0.0
```

## Plugins

Public plugins from wordpress.org are listed in `plugins.txt`:

```txt
plugin-slug:version
plugin-slug:*
```

`plugin-slug:*` installs the latest version from wordpress.org.

Private or custom plugins go in `local-plugins/` as `.zip` files. The container installs them after WordPress is set up.

On the **first** container start, all plugins from `plugins.txt` are force-installed and synced. Later starts **skip** install unless you set `WP_FORCE_INSTALL` in `.env`:

```env
WP_FORCE_INSTALL=1
```

Accepted values: `1`, `true`, `yes`, `on`.

All config files are optional. If `WP_CONFIG_PATH` has no `php.ini`, `plugins.txt`, or `local-plugins/`, the container skips that step and starts normally. Place these files in `./docker-config` in your project.

## Container Commands

Scripts and WP-CLI are available inside the running container. Replace `wordpress` with your `container_name` if different.

### Shell access

```sh
docker compose exec wordpress sh
# or
docker exec -it wordpress sh
```

### Built-in scripts

These run automatically on container start (in the background). You can also run them manually:

| Script | Path | What it does |
|--------|------|--------------|
| Install plugins | `/usr/local/bin/install-plugins.sh` | Sync plugins from `plugins.txt`, install local `.zip` files, remove plugins not in the list |
| Migrate URL | `/usr/local/bin/migrate-url.sh` | Update `siteurl`/`home` to `WP_SITEURL`, run `search-replace`, update Elementor URLs |
| Clear cache | `/usr/local/bin/cache-clear.sh` | Flush object cache, Redis (if present), and transients |
| WP cron loop | `/usr/local/bin/wp-cron.sh` | Run due cron events every 60s (managed by supervisor) |
| Run cron once | `/usr/local/bin/cron.sh` | Run due cron events once |
| Backup | `/usr/local/bin/backup.sh` | Export DB + `wp-content` (themes, uploads, mu-plugins, plugins) to `/docker/backups` |

```sh
# Create a backup (saved to ./backups on host)
docker compose exec wordpress sh /usr/local/bin/backup.sh

# Keep only the 5 most recent backups
docker compose exec -e WP_BACKUP_KEEP=5 wordpress sh /usr/local/bin/backup.sh
# Re-sync plugins (after editing plugins.txt)
docker compose exec -e WP_FORCE_INSTALL=1 wordpress sh /usr/local/bin/install-plugins.sh

# Re-run URL migration (only runs once by default; clear flag first to force)
docker compose exec wordpress sh -c 'wp option delete _env_url_migrated --path=/var/www/html --allow-root'
docker compose exec wordpress sh /usr/local/bin/migrate-url.sh

# Clear all caches
docker compose exec wordpress sh /usr/local/bin/cache-clear.sh

# Run WP cron manually
docker compose exec wordpress sh /usr/local/bin/cron.sh
```

### WP-CLI

WP-CLI is installed at `/usr/local/bin/wp`. Use `--path=/var/www/html --allow-root` for all commands:

```sh
# Core
docker compose exec wordpress wp core is-installed --path=/var/www/html --allow-root
docker compose exec wordpress wp core version --path=/var/www/html --allow-root

# Plugins
docker compose exec wordpress wp plugin list --path=/var/www/html --allow-root
docker compose exec wordpress wp plugin install contact-form-7 --activate --path=/var/www/html --allow-root
docker compose exec wordpress wp plugin update --all --path=/var/www/html --allow-root

# Themes
docker compose exec wordpress wp theme list --path=/var/www/html --allow-root
docker compose exec wordpress wp theme activate twentytwentyfour --path=/var/www/html --allow-root

# Database
docker compose exec wordpress wp db check --path=/var/www/html --allow-root
docker compose exec wordpress wp search-replace 'http://old.url' 'http://new.url' --all-tables --path=/var/www/html --allow-root

# Cache & cron
docker compose exec wordpress wp cache flush --path=/var/www/html --allow-root
docker compose exec wordpress wp cron event list --path=/var/www/html --allow-root
docker compose exec wordpress wp cron event run --due-now --path=/var/www/html --allow-root

# Elementor (if installed)
docker compose exec wordpress wp elementor flush-css --path=/var/www/html --allow-root
docker compose exec wordpress wp elementor replace-urls 'http://old.url' 'http://new.url' --path=/var/www/html --allow-root

# Users
docker compose exec wordpress wp user list --path=/var/www/html --allow-root
docker compose exec wordpress wp user create admin admin@example.com --role=administrator --user_pass=secret --path=/var/www/html --allow-root
```

For plugin/theme operations while plugins are broken, add `--skip-plugins --skip-themes` (used internally by `install-plugins.sh`).

### Backup

Backups are written to `/docker/backups` inside the container (mount `./backups` via `WP_BACKUP_PATH`).

Each run creates `wp-backup-YYYYMMDD-HHMMSS.tar.gz` containing:

```txt
database.sql
wp-content/themes/
wp-content/uploads/
wp-content/mu-plugins/
wp-content/plugins/
manifest.txt
```

`plugins` is included because the plugins directory is not mounted on the host.

Restore example:

```sh
# Extract on host
tar -xzf backups/wp-backup-20260101-120000.tar.gz -C /tmp
dir=/tmp/wp-backup-20260101-120000

# Restore files
cp -a "$dir/wp-content/"* ./wp-content/

# Restore database
docker compose exec -i wordpress wp db import - --path=/var/www/html --allow-root < "$dir/database.sql"
```

### Script environment variables

| Variable | Default | Used by |
|----------|---------|---------|
| `WP_PLUGINS_FILE` | `/docker/config/plugins.txt` | `install-plugins.sh` |
| `WP_LOCAL_PLUGINS_PATH` | `/docker/config/local-plugins` | `install-plugins.sh` |
| `WP_FORCE_INSTALL` | _(empty)_ | `install-plugins.sh` — set to `1` to force reinstall |
| `WP_SITEURL` | _(required for migration)_ | `migrate-url.sh` |
| `WP_BACKUP_DIR` | `/docker/backups` | `backup.sh` |
| `WP_BACKUP_KEEP` | _(empty)_ | `backup.sh` — max archives to keep |
| `PHP_INI_FILE` | `/docker/config/php.ini` | `start-container` |

## Publish Image

To push to your own registry:

```sh
docker tag reusable-wordpress:php8.4-apache your-registry/reusable-wordpress:php8.4-apache
docker push your-registry/reusable-wordpress:php8.4-apache
```

## GitHub Actions

Workflow `.github/workflows/build-image.yml` builds the image from `./docker`.

- PR merged into `main`/`master`: build and push to GHCR
- Manual run: change base image via `wordpress_image` input
- Runner: GitHub-hosted (`ubuntu-latest`), free for public repos
- Multi-arch: `linux/amd64`, `linux/arm64`

Default image on GitHub Container Registry:

```txt
ghcr.io/thang-dv/wp-docker
```
