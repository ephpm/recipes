# Aimeos (the aimeos/aimeos Laravel shop distribution) on ePHPm.
#
# One container replaces nginx/apache + php-fpm (Laravel Sail upstream):
# ePHPm serves public/ and runs PHP. A `jobs` sidecar from the same image
# runs Aimeos's cron jobs (`artisan aimeos:jobs ...`).
#
# Build args:
#   EPHPM_TAG       ephpm/ephpm image tag (default v0.11.3-php8.5)
#   AIMEOS_VERSION  aimeos/aimeos release tag (default 2026.10.1)

ARG EPHPM_TAG=v0.11.3-php8.5
ARG AIMEOS_VERSION=2026.10.1

# ── Stage 1: the release source ──────────────────────────────────────────────
FROM docker.io/library/alpine:3.20 AS src
ARG AIMEOS_VERSION
RUN apk add --no-cache curl tar
RUN mkdir /src \
    && curl -fsSL "https://github.com/aimeos/aimeos/archive/refs/tags/${AIMEOS_VERSION}.tar.gz" \
       | tar xz --strip-components=1 -C /src \
    && rm -rf /src/tests /src/docker-compose.yml /src/.github

# ── Stage 2: PHP dependencies ────────────────────────────────────────────────
FROM docker.io/library/composer:2 AS vendor
WORKDIR /app
COPY --from=src /src /app
# --no-scripts: package discovery and asset publishing run below on the
# embedded PHP; the interactive create-project setup is entrypoint.sh's job.
RUN composer install --no-dev --no-scripts --no-interaction --prefer-dist \
        --ignore-platform-reqs --optimize-autoloader --no-progress

# ── Stage 3: the Breeze login/profile pages' Vite bundle ─────────────────────
FROM docker.io/library/node:22-alpine AS assets
WORKDIR /app
COPY --from=vendor /app /app
RUN npm ci --no-audit --no-fund && npm run build

# ── Stage 4: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

COPY --from=vendor /app /app
COPY --from=assets /app/public/build /app/public/build
COPY ephpm.toml /etc/ephpm/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
# `php` on PATH for tools that re-invoke PHP, and PHP_BINARY pointing at it:
# Laravel's scheduler / Symfony's PhpExecutableFinder otherwise return the
# PHP_BINARY constant, which is `ephpm` under `ephpm php` (ephpm#558).
RUN printf '#!/bin/sh\nexec ephpm php "$@"\n' > /usr/local/bin/php && chmod +x /usr/local/bin/php
ENV PHP_BINARY=/usr/local/bin/php
WORKDIR /app
RUN chmod +x /usr/local/bin/entrypoint.sh \
    && mkdir -p storage/framework/cache/data storage/framework/sessions storage/framework/views storage/logs storage/tmp bootstrap/cache public/aimeos \
    # the composer scripts skipped above (post-autoload-dump / post-update-cmd)
    && ephpm php artisan package:discover --ansi \
    && ephpm php artisan vendor:publish --tag=laravel-assets --ansi --force \
    && ephpm php artisan vendor:publish --tag=public --ansi --force \
    && mkdir -p /usr/local/share/aimeos && cp -a storage /usr/local/share/aimeos/storage

ENV APP_ENV=production \
    APP_DEBUG=false \
    LOG_CHANNEL=stderr

VOLUME ["/app/storage", "/app/public/aimeos"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
