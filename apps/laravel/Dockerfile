# Laravel on ePHPm.
#
# Builds the stock `laravel/laravel` application skeleton (LARAVEL_VERSION)
# and runs it on ePHPm in per-request mode, or — with compose.worker.yml —
# in persistent worker mode through the native Octane driver
# (ephpm/octane-driver). Replace the `create-project` line with
# `COPY . /app` + `composer install` for your own application.
#
# Build args:
#   EPHPM_TAG        ephpm/ephpm image tag (default v0.11.3-php8.5)
#   LARAVEL_VERSION  laravel/laravel constraint for create-project (default ^12.0)

ARG EPHPM_TAG=v0.11.3-php8.5
ARG LARAVEL_VERSION=^12.0

# ── Stage 1: Composer ────────────────────────────────────────────────────────
# Scripts are skipped here (no PHP runtime that matches ePHPm's); package
# discovery runs on the embedded PHP in the final stage.
FROM docker.io/library/composer:2 AS vendor
ARG LARAVEL_VERSION
RUN composer create-project --no-interaction --prefer-dist --no-scripts --no-dev \
        --ignore-platform-reqs laravel/laravel /app "${LARAVEL_VERSION}"
WORKDIR /app
# predis: Laravel's Redis client for the KV-backed cache/session variant.
# laravel/octane + ephpm/octane-driver (+ its ephpm/worker base, listed as a
# separate VCS repo because Composer does not resolve VCS repos transitively):
# the worker-mode variant. Both are harmless in per-request mode.
# Repository type `git` (plain clone), not `vcs` — `vcs` goes through the
# GitHub API and its anonymous rate limit.
RUN composer config repositories.ephpm-octane git https://github.com/ephpm/octane-driver.git \
    && composer config repositories.ephpm-worker git https://github.com/ephpm/php-worker.git \
    && composer config minimum-stability dev && composer config prefer-stable true \
    && composer require --no-interaction --no-scripts --update-no-dev --ignore-platform-reqs \
        predis/predis:^3.0 laravel/octane:^2.0 ephpm/octane-driver:^0.1

# ── Stage 2: runtime ─────────────────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}
COPY --from=vendor /app /app
COPY ephpm.toml ephpm.embedded.toml ephpm.worker.toml /etc/ephpm/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
WORKDIR /app
RUN chmod +x /usr/local/bin/entrypoint.sh \
    && rm -f .env \
    && ephpm php artisan package:discover --ansi \
    && ephpm php artisan vendor:publish --tag=laravel-assets --ansi --force \
    && mkdir -p /var/lib/ephpm storage/framework/{cache/data,sessions,views} storage/logs bootstrap/cache

ENV APP_ENV=production \
    APP_DEBUG=false \
    LOG_CHANNEL=stderr \
    DB_CONNECTION=mysql \
    DB_HOST=127.0.0.1 \
    DB_PORT=3306 \
    DB_DATABASE=laravel \
    DB_USERNAME=root \
    DB_PASSWORD= \
    SESSION_DRIVER=database \
    CACHE_STORE=database \
    QUEUE_CONNECTION=database \
    EPHPM_APP_BASE=/app

VOLUME ["/app/storage"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
