# Speedtest Tracker on ePHPm.
#
# One container replaces the linuxserver/speedtest-tracker image's nginx +
# php-fpm + s6 (with its cron and queue runner): ePHPm serves public/ and
# runs PHP; the scheduler and the queue worker are sidecars from the same
# image. The Ookla Speedtest CLI is installed exactly as upstream does.
#
# Build args:
#   EPHPM_TAG            ephpm/ephpm image tag (default v0.11.3-php8.5)
#   SPEEDTEST_TRACKER_VERSION   release tag to bake in (default v1.15.0)
#   OOKLA_VERSION        Ookla Speedtest CLI version (default 1.2.0, as upstream)
#
# Speedtest Tracker publishes no tarball with vendor/ or built assets, so the
# image runs `composer install` and `npm run build` (Vite) in build stages.

ARG EPHPM_TAG=v0.11.3-php8.5
ARG SPEEDTEST_TRACKER_VERSION=v1.15.0
ARG OOKLA_VERSION=1.2.0

# ── Stage 1: fetch the release source + the Ookla CLI ────────────────────────
FROM docker.io/library/alpine:3.20 AS src
ARG SPEEDTEST_TRACKER_VERSION
ARG OOKLA_VERSION
RUN apk add --no-cache curl tar
RUN mkdir /src \
    && curl -fsSL "https://github.com/alexjustesen/speedtest-tracker/archive/refs/tags/${SPEEDTEST_TRACKER_VERSION}.tar.gz" \
       | tar xz --strip-components=1 -C /src \
    && rm -rf /src/tests /src/.github /src/.devcontainer /src/docker /src/compose.yaml
# the same download upstream's Dockerfile performs (x86_64 / aarch64)
RUN ARCH="$(uname -m)" && case "$ARCH" in x86_64) P=x86_64 ;; aarch64) P=aarch64 ;; *) echo "unsupported arch $ARCH" && exit 1 ;; esac \
    && mkdir /ookla \
    && curl -fsSL "https://install.speedtest.net/app/cli/ookla-speedtest-${OOKLA_VERSION}-linux-${P}.tgz" \
       | tar xz -C /ookla speedtest

# ── Stage 2: PHP dependencies ────────────────────────────────────────────────
FROM docker.io/library/composer:2 AS vendor
WORKDIR /app
COPY --from=src /src /app
RUN composer install --no-dev --no-scripts --no-interaction --prefer-dist \
        --ignore-platform-reqs --optimize-autoloader --no-progress

# ── Stage 3: front-end build (Vite) ──────────────────────────────────────────
# Node from Alpine's packages on the composer image (one fewer base image
# to pull); the result is the same public/build directory.
FROM docker.io/library/composer:2 AS assets
WORKDIR /app
RUN apk add --no-cache nodejs npm
COPY --from=vendor /app /app
RUN npm ci --no-audit --no-fund && npm run build

# ── Stage 4: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

COPY --from=vendor /app /app
COPY --from=assets /app/public/build /app/public/build
COPY --from=src /ookla/speedtest /usr/local/bin/speedtest
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
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/speedtest \
    # the composer scripts skipped above, on the PHP that will run the app
    && cp /app/.env.example /app/.env && ephpm php artisan package:discover --ansi \
    && ephpm php artisan filament:upgrade --ansi && rm /app/.env \
    && mkdir -p /data \
    # pristine copy, used by entrypoint.sh to seed an empty storage volume
    && mkdir -p /usr/local/share/speedtest-tracker \
    && cp -a /app/storage /usr/local/share/speedtest-tracker/storage

VOLUME ["/data", "/app/storage"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
