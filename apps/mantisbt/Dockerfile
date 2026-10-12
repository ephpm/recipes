# MantisBT on ePHPm.
#
# One container replaces Apache + mod_php (or nginx + php-fpm): ePHPm serves
# MantisBT and runs PHP; the REST API's Slim front controller is the
# fallback for every path that is not a file.
#
# Build args:
#   EPHPM_TAG        ephpm/ephpm image tag (default v0.11.3-php8.5)
#   MANTIS_VERSION   release tag (default 2.28.4)

ARG EPHPM_TAG=v0.11.3-php8.5
ARG MANTIS_VERSION=2.28.4

# ── Stage 1: release source + Composer dependencies ──────────────────────────
FROM docker.io/library/composer:2 AS src
ARG MANTIS_VERSION
RUN mkdir /src \
    && curl -fsSL "https://github.com/mantisbt/mantisbt/archive/refs/tags/release-${MANTIS_VERSION}.tar.gz" \
       | tar xz --strip-components=1 -C /src \
    && cd /src \
    && composer install --no-dev --no-interaction --prefer-dist --ignore-platform-reqs --optimize-autoloader --no-progress \
    && rm -rf tests docbook build .github phpunit.xml

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

COPY --from=src /src /app
COPY php /usr/local/bin/php
COPY ephpm.toml /etc/ephpm/ephpm.toml
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY setup.php /usr/local/share/mantisbt/setup.php
RUN chmod +x /usr/local/bin/php /usr/local/bin/entrypoint.sh \
    && cp -a /app/config /usr/local/share/mantisbt/config \
    && mkdir -p /var/lib/mantisbt/attachments

WORKDIR /app
VOLUME ["/app/config", "/var/lib/mantisbt/attachments"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
