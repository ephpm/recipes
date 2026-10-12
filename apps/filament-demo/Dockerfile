# Filament Demo (filamentphp/demo) on ePHPm.
#
# One container replaces nginx + php-fpm (or `php artisan serve` /
# Octane): ePHPm serves public/ and runs PHP. A `scheduler` sidecar from
# the same image runs Laravel's scheduler (the demo's hourly database reset).
#
# Build args:
#   EPHPM_TAG     ephpm/ephpm image tag (default v0.11.3-php8.5)
#   DEMO_COMMIT   filamentphp/demo commit on the 5.x branch (it has no release tags)

ARG EPHPM_TAG=v0.11.3-php8.5
ARG DEMO_COMMIT=866461e44624ed858575151d39d1069e297fc40e

# ── Stage 1: the source ──────────────────────────────────────────────────────
FROM docker.io/library/alpine:3.20 AS src
ARG DEMO_COMMIT
RUN apk add --no-cache curl tar
RUN mkdir /src \
    && curl -fsSL "https://github.com/filamentphp/demo/archive/${DEMO_COMMIT}.tar.gz" \
       | tar xz --strip-components=1 -C /src \
    && rm -rf /src/tests /src/.github /src/.agents /src/.amp /src/.claude /src/.mcp.json /src/CLAUDE.md

# ── Stage 2: PHP dependencies ────────────────────────────────────────────────
FROM docker.io/library/composer:2 AS vendor
WORKDIR /app
COPY --from=src /src /app
RUN composer install --no-dev --no-scripts --no-interaction --prefer-dist \
        --ignore-platform-reqs --optimize-autoloader --no-progress

# ── Stage 3: the Vite bundle (the panel theme) ───────────────────────────────
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
# `php` on PATH, and PHP_BINARY pointing at it: Laravel builds every
# scheduled command as `<PHP binary> artisan ...`, and Symfony's
# PhpExecutableFinder returns the PHP_BINARY constant (`ephpm` under
# `ephpm php`, ephpm#558) unless the PHP_BINARY environment variable is set —
# without this the scheduler's commands silently fail (issues/pterodactyl.md).
RUN printf '#!/bin/sh\nexec ephpm php "$@"\n' > /usr/local/bin/php && chmod +x /usr/local/bin/php
ENV PHP_BINARY=/usr/local/bin/php
WORKDIR /app
RUN chmod +x /usr/local/bin/entrypoint.sh \
    && mkdir -p storage/framework/cache/data storage/framework/sessions storage/framework/views storage/logs storage/app/public bootstrap/cache \
    # the composer scripts skipped above (post-autoload-dump / post-update-cmd)
    && ephpm php artisan package:discover --ansi \
    && ephpm php artisan filament:upgrade --ansi \
    && ephpm php artisan vendor:publish --tag=laravel-assets --ansi --force \
    && ln -sfn /app/storage/app/public /app/public/storage \
    && mkdir -p /usr/local/share/filament-demo && cp -a storage /usr/local/share/filament-demo/storage

ENV APP_ENV=production \
    APP_DEBUG=false \
    LOG_CHANNEL=stderr

VOLUME ["/app/storage"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
