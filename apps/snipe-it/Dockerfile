# Snipe-IT on ePHPm.
#
# One container replaces the official snipe/snipe-it image (Apache + PHP +
# cron): ePHPm serves public/, runs PHP and can provide the Redis-compatible
# KV store for cache/sessions.
#
# Build args:
#   EPHPM_TAG          ephpm/ephpm image tag (default v0.11.3-php8.5)
#   SNIPEIT_VERSION    Snipe-IT release tag to bake in (default v8.8.0)
#
# Snipe-IT publishes no tarball with vendor/, so dependencies are installed
# in a composer:2 stage; the front-end bundles are committed upstream
# (public/js/build, public/css/build), so there is no Node stage.

ARG EPHPM_TAG=v0.11.3-php8.5
ARG SNIPEIT_VERSION=v8.8.0

# ── Stage 1: fetch the release source ────────────────────────────────────────
FROM docker.io/library/alpine:3.20 AS src
ARG SNIPEIT_VERSION
RUN apk add --no-cache curl tar
RUN mkdir /src \
    && curl -fsSL "https://github.com/grokability/snipe-it/archive/refs/tags/${SNIPEIT_VERSION}.tar.gz" \
       | tar xz --strip-components=1 -C /src \
    && rm -rf /src/tests /src/.github /src/.ai /src/ansible /src/Vagrantfile /src/sample_csvs

# ── Stage 2: PHP dependencies ────────────────────────────────────────────────
FROM docker.io/library/composer:2 AS vendor
WORKDIR /app
COPY --from=src /src /app
# --no-scripts: post-autoload-dump (package:discover + livewire asset
# publish) runs below on the embedded PHP instead of the composer image's.
RUN composer install --no-dev --no-scripts --no-interaction --prefer-dist \
        --ignore-platform-reqs --optimize-autoloader --no-progress

# ── Stage 3: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

COPY --from=vendor /app /app
COPY env.template /usr/local/share/snipe-it/env.template
COPY ephpm.toml /etc/ephpm/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
# `php` on PATH: Laravel's scheduler and tools that re-invoke PHP look for
# a `php` binary (PHP_BINARY is `ephpm` here), so give them `ephpm php`.
RUN printf '#!/bin/sh\nexec ephpm php "$@"\n' > /usr/local/bin/php && chmod +x /usr/local/bin/php
WORKDIR /app
RUN chmod +x /usr/local/bin/entrypoint.sh \
    # the composer scripts skipped above, on the PHP that will run the app
    && cp /usr/local/share/snipe-it/env.template /app/.env \
    && ephpm php artisan package:discover --ansi \
    && ephpm php artisan vendor:publish --force --tag=livewire:assets --ansi \
    && rm /app/.env \
    # Passport's migrations, which the official startup script copies in
    && cp -an /app/vendor/laravel/passport/database/migrations/. /app/database/migrations/ \
    # pristine copies, used by entrypoint.sh to seed empty volumes
    && cp -a /app/storage /usr/local/share/snipe-it/storage \
    && cp -a /app/public/uploads /usr/local/share/snipe-it/uploads

VOLUME ["/app/storage", "/app/public/uploads"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
