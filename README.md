# Reusable WordPress Docker Image

This repository builds a reusable WordPress Docker image for other WP projects.

The image includes:

- Configurable WordPress base image via `WORDPRESS_IMAGE`
- WP-CLI
- Supervisor for WP cron
- URL migration script based on `WP_SITEURL`
- Cache clearing script
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
      - ${WP_CONTENT_PATH:-./wp-content}:/var/www/html/wp-content
      - ${WP_CONFIG_PATH:-./docker-config}:/docker/config:ro
```

Example `.env`:

```env
WP_BIND_HOST=127.0.0.1
WP_PORT=8084
WP_SITEURL=http://localhost:8084
WP_HOME=http://localhost:8084
WP_CONTENT_PATH=./wp-content
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
