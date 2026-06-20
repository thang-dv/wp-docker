# Reusable WordPress Docker Image

Repo này chỉ dùng để build một Docker image WordPress có thể tái sử dụng cho các project WP khác.

Image có sẵn:

- WordPress base image tùy biến qua `WORDPRESS_IMAGE`
- WP-CLI
- supervisor chạy WP cron
- script migrate URL theo `WP_SITEURL`
- script clear cache
- script cài plugin từ `plugins.txt` và các file `.zip` trong `local-plugins/` nếu có
- `php.ini` custom nếu có trong config mount

## Image Trên GHCR

Image **public** — pull trực tiếp, không cần login. Hỗ trợ `linux/amd64` và `linux/arm64` (Apple Silicon không cần `platform: linux/amd64`):

```sh
docker pull ghcr.io/thang-dv/wp-docker:latest
```

Image mặc định:

```txt
ghcr.io/thang-dv/wp-docker:latest
```

Workflow sẽ publish thêm tag theo branch, git tag và SHA. Ví dụ:

```txt
ghcr.io/thang-dv/wp-docker:dev
ghcr.io/thang-dv/wp-docker:main
ghcr.io/thang-dv/wp-docker:v1.0.0
ghcr.io/thang-dv/wp-docker:sha-<commit>
```

Lần publish đầu tiên, org GHCR package mặc định **private**. Workflow sẽ tự set **public** sau khi push. Nếu API không đủ quyền, vào **Package settings → Change visibility → Public**:

`https://github.com/orgs/thang-dv/packages/container/wp-docker/settings`

## Build Local Khi Cần

```sh
docker build \
  --build-arg WORDPRESS_IMAGE=wordpress:php8.4-apache \
  -t reusable-wordpress:php8.4-apache \
  ./docker
```

`docker-compose.yaml` trong repo này chỉ là ví dụ cách consume image, không phải stack đầy đủ. Database nên nằm ở project WP thật hoặc external service của bạn.

## Dùng Trong Project WP Khác

Trong project WordPress thật, dùng image từ GHCR và để option trong `.env`:

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

Ví dụ `.env`:

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

Nếu muốn pin version ổn định hơn, dùng tag release hoặc SHA thay cho `latest`:

```yaml
services:
  wordpress:
    image: ghcr.io/thang-dv/wp-docker:v1.0.0
```

## Plugin

Plugin public trên wordpress.org khai báo trong `plugins.txt`:

```txt
plugin-slug:version
plugin-slug:*
```

Trong đó `plugin-slug:*` sẽ cài bản mới nhất từ wordpress.org.

Plugin private hoặc plugin tự viết đặt file `.zip` vào `local-plugins/`. Container sẽ tự cài sau khi WordPress đã install xong.

Các file config đều optional. Nếu `WP_CONFIG_PATH` không có `php.ini`, `plugins.txt`, hoặc `local-plugins/`, container sẽ bỏ qua phần tương ứng và vẫn start bình thường. Nên đặt các file này trong `./docker-config` của project thật.

## Publish Image

Nếu muốn đẩy lên registry riêng:

```sh
docker tag reusable-wordpress:php8.4-apache your-registry/reusable-wordpress:php8.4-apache
docker push your-registry/reusable-wordpress:php8.4-apache
```

## GitHub Actions

Workflow `.github/workflows/build-image.yml` sẽ build image từ `./docker`.

- Pull request merge vào `main`/`master`: build và push image lên GHCR.
- Manual run: có thể đổi base image bằng input `wordpress_image`.
- Runner: GitHub-hosted (`ubuntu-latest`), free vì repo public.

Image mặc định trên GitHub Container Registry:

```txt
ghcr.io/thang-dv/wp-docker
```
