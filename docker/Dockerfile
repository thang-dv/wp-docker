ARG WORDPRESS_IMAGE=wordpress:php8.4-apache
FROM ${WORDPRESS_IMAGE}

WORKDIR /var/www/html

RUN apt-get update && apt-get install -y --no-install-recommends \
    supervisor \
    curl \
    default-mysql-client \
 && rm -rf /var/lib/apt/lists/*

# install WP-CLI
RUN curl -sO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
 && chmod +x wp-cli.phar \
 && mv wp-cli.phar /usr/local/bin/wp

# disable wp-cron
RUN echo "define('DISABLE_WP_CRON', true);" >> /usr/src/wordpress/wp-config-extra.php

# copy scripts
COPY wp-cron.sh /usr/local/bin/wp-cron.sh
COPY migrate-url.sh /usr/local/bin/migrate-url.sh
COPY cache-clear.sh /usr/local/bin/cache-clear.sh
COPY install-plugins.sh /usr/local/bin/install-plugins.sh

RUN chmod +x /usr/local/bin/*.sh

# supervisor config
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# start script
COPY start-container /usr/local/bin/start-container
RUN chmod +x /usr/local/bin/start-container

EXPOSE 80
ENTRYPOINT ["start-container"]
