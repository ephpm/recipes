# Pelican Panel on ePHPm.
#
# One container replaces the official ghcr.io/pelican/panel image's Caddy +
# php-fpm + supervisord: ePHPm serves public/ and runs PHP; the scheduler
# and the queue worker are sidecars from the same image.
#
# Build args:
#   EPHPM_TAG         ephpm/ephpm image tag (default v0.11.3-php8.5)
#   PELICAN_VERSION   Pelican release to bake in (default v1.0.0-rc.1)
#
# The release tarball ships the built front-end (public/build) but not
# vendor/, so dependencies are installed in a composer:2 stage.

ARG EPHPM_TAG=v0.11.3-php8.5
ARG PELICAN_VERSION=v1.0.0-rc.1

# ── Stage 1: fetch the release ───────────────────────────────────────────────
FROM docker.io/library/alpine:3.20 AS src
ARG PELICAN_VERSION
RUN apk add --no-cache curl tar
RUN mkdir /src \
    && curl -fsSL "https://github.com/pelican-dev/panel/releases/download/${PELICAN_VERSION}/panel.tar.gz" \
       | tar xz -C /src \
    && rm -rf /src/docker /src/Dockerfile /src/Dockerfile.base /src/Dockerfile.dev \
       /src/compose*.yml /src/package.json /src/yarn.lock /src/vite.config.js

# ── Stage 2: PHP dependencies ────────────────────────────────────────────────
FROM docker.io/library/composer:2 AS vendor
WORKDIR /app
COPY --from=src /src /app
RUN composer install --no-dev --no-scripts --no-interaction --prefer-dist \
        --ignore-platform-reqs --optimize-autoloader --no-progress

# ── Stage 3: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

COPY --from=vendor /app /app
COPY ephpm.toml /etc/ephpm/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
# `php` on PATH: Laravel's scheduler and tools that re-invoke PHP look for
# a `php` binary (PHP_BINARY is `ephpm` here), so give them `ephpm php`.
RUN printf '#!/bin/sh\nexec ephpm php "$@"\n' > /usr/local/bin/php && chmod +x /usr/local/bin/php
# Laravel builds scheduled commands as `<PHP binary> artisan ...`; the binary
# comes from Symfony's PhpExecutableFinder, which returns the PHP_BINARY
# constant (`ephpm`, ephpm#558) unless the PHP_BINARY *environment variable*
# is set. Without this every `$schedule->command(...)` silently fails
# (issues/pterodactyl.md).
ENV PHP_BINARY=/usr/local/bin/php
WORKDIR /app
RUN chmod +x /usr/local/bin/entrypoint.sh \
    # the composer script skipped above, on the PHP that will run the app
    && cp /app/.env.example /app/.env && ephpm php artisan package:discover --ansi && rm /app/.env \
    # the official image's layout: everything persistent under /pelican-data
    && mkdir -p /pelican-data/database /pelican-data/storage /pelican-data/plugins \
    && ln -sfn /pelican-data/.env /app/.env \
    && ln -sfn /pelican-data/database/database.sqlite /app/database/database.sqlite \
    && rm -rf /app/storage/app/public /app/public/storage \
    && ln -sfn /pelican-data/storage /app/storage/app/public \
    && ln -sfn /pelican-data/storage /app/public/storage

VOLUME ["/pelican-data"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
