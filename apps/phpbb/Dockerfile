# phpBB on ePHPm.
#
# One container replaces nginx/Apache + php-fpm: ePHPm serves the board's
# scripts and assets and routes app.php/… controller URLs; phpBB's CLI
# installer and bin/phpbbcli.php run on the embedded PHP.
#
# download.phpbb.com refuses non-browser clients, so the source comes from
# the GitHub release tag and vendor/ is installed with Composer.
#
# Build args:
#   EPHPM_TAG      ephpm/ephpm image tag (default v0.11.3-php8.5)
#   PHPBB_VERSION  phpBB release to bake in (default 3.3.19)

ARG EPHPM_TAG=v0.11.3-php8.5
ARG PHPBB_VERSION=3.3.19

# ── Stage 1: the release tag's phpBB/ tree + Composer dependencies ───────────
FROM docker.io/library/composer:2 AS src
ARG PHPBB_VERSION
RUN mkdir -p /tmp/phpbb \
    && curl -fsSL "https://github.com/phpbb/phpbb/archive/refs/tags/release-${PHPBB_VERSION}.tar.gz" \
       | tar xz --strip-components=1 -C /tmp/phpbb \
    && mv /tmp/phpbb/phpBB /src && rm -rf /tmp/phpbb \
    && cd /src \
    && composer install --no-dev --no-scripts --no-interaction --prefer-dist --ignore-platform-reqs --optimize-autoloader \
    && rm -rf develop composer.phar

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

COPY --from=src /src /var/www/html
COPY php /usr/local/bin/php
COPY ephpm.toml /etc/ephpm/ephpm.toml
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/php /usr/local/bin/entrypoint.sh \
    && mkdir -p /var/phpbb \
    # pristine copies, used by entrypoint.sh to seed empty volumes
    && mkdir -p /usr/local/share/phpbb \
    && cp -a /var/www/html/ext /var/www/html/files /var/www/html/store /var/www/html/images/avatars/upload \
             /usr/local/share/phpbb/ \
    && mv /usr/local/share/phpbb/upload /usr/local/share/phpbb/avatars

WORKDIR /var/www/html
VOLUME ["/var/phpbb", "/var/www/html/ext", "/var/www/html/files", "/var/www/html/store", "/var/www/html/images/avatars/upload"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
