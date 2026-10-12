# Krayin CRM on ePHPm.
#
# Krayin publishes no production image; this replaces the usual
# nginx/apache + php-fpm host with ePHPm serving public/ and running PHP.
#
# Build args:
#   EPHPM_TAG        ephpm/ephpm image tag (default v0.11.3-php8.5)
#   KRAYIN_VERSION   Krayin release tag to bake in (default v2.2.6)
#
# Krayin commits its built admin assets (public/admin/build), so only a
# Composer stage is needed — no Node build.

ARG EPHPM_TAG=v0.11.3-php8.5
ARG KRAYIN_VERSION=v2.2.6

# ── Stage 1: fetch the release source ────────────────────────────────────────
FROM docker.io/library/alpine:3.20 AS src
ARG KRAYIN_VERSION
RUN apk add --no-cache curl tar
RUN mkdir /src \
    && curl -fsSL "https://github.com/krayin/laravel-crm/archive/refs/tags/${KRAYIN_VERSION}.tar.gz" \
       | tar xz --strip-components=1 -C /src \
    && rm -rf /src/tests /src/.github /src/docker-compose.yml

# ── Stage 2: PHP dependencies ────────────────────────────────────────────────
FROM docker.io/library/composer:2 AS vendor
WORKDIR /app
COPY --from=src /src /app
# --no-scripts: post-autoload-dump (artisan package:discover) runs below on
# the embedded PHP instead of the composer image's PHP.
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
    && mkdir -p /var/lib/ephpm \
    # the composer script skipped above, on the PHP that will run the app
    && cp .env.example .env && ephpm php artisan package:discover --ansi && rm .env \
    # public/storage -> storage/app/public (uploaded files, avatars)
    && ln -sfn /app/storage/app/public /app/public/storage \
    # pristine copy, used by entrypoint.sh to seed an empty storage volume
    && mkdir -p /usr/local/share/krayin \
    && cp -a /app/storage /usr/local/share/krayin/storage

VOLUME ["/app/storage"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
