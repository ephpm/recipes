# Pterodactyl Panel on ePHPm.
#
# One container replaces the official ghcr.io/pterodactyl/panel image's
# nginx + php-fpm + supervisord + crond: ePHPm serves public/ and runs PHP;
# the queue worker and the scheduler are sidecars from the same image.
#
# Build args:
#   EPHPM_TAG             ephpm/ephpm image tag (default v0.11.3-php8.5)
#   PTERODACTYL_VERSION   Panel release to bake in (default v1.15.1)
#
# The release tarball ships the built front-end (public/assets) but not
# vendor/, so dependencies are installed in a composer:2 stage.

ARG EPHPM_TAG=v0.11.3-php8.5
ARG PTERODACTYL_VERSION=v1.15.1

# ── Stage 1: fetch the release ───────────────────────────────────────────────
FROM docker.io/library/alpine:3.20 AS src
ARG PTERODACTYL_VERSION
RUN apk add --no-cache curl tar
RUN mkdir /src \
    && curl -fsSL "https://github.com/pterodactyl/panel/releases/download/${PTERODACTYL_VERSION}/panel.tar.gz" \
       | tar xz -C /src \
    && rm -rf /src/Dockerfile /src/docker-compose.example.yml /src/package.json /src/yarn.lock \
       /src/webpack.config.js /src/resources/scripts /src/.github

# ── Stage 2: PHP dependencies ────────────────────────────────────────────────
FROM docker.io/library/composer:2 AS vendor
WORKDIR /app
COPY --from=src /src /app
RUN composer install --no-dev --no-scripts --no-interaction --prefer-dist \
        --ignore-platform-reqs --optimize-autoloader --no-progress

# ── Stage 3: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

# The panel ships a Laravel schema dump (database/schema/mysql-schema.sql)
# that `migrate` loads through the `mysql` CLI on a fresh database — the
# official image installs mysql-client for the same reason.
RUN apt-get update \
    && apt-get install -y --no-install-recommends mariadb-client \
    && rm -rf /var/lib/apt/lists/*

COPY --from=vendor /app /app
COPY ephpm.toml /etc/ephpm/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
# `php` on PATH: Laravel's scheduler and tools that re-invoke PHP look for
# a `php` binary (PHP_BINARY is `ephpm` here), so give them `ephpm php`.
RUN printf '#!/bin/sh\nexec ephpm php "$@"\n' > /usr/local/bin/php && chmod +x /usr/local/bin/php
WORKDIR /app
RUN chmod +x /usr/local/bin/entrypoint.sh \
    && mkdir -p bootstrap/cache storage/logs storage/framework/sessions storage/framework/views storage/framework/cache /app/var \
    # the composer script skipped above, on the PHP that will run the app
    && cp .env.example .env && ephpm php artisan package:discover --ansi && rm .env bootstrap/cache/*.php \
    # the official image's layout: .env lives in the /app/var volume
    && ln -sfn /app/var/.env /app/.env

VOLUME ["/app/var", "/app/storage/logs"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
