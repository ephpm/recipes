# Cachet 3 on ePHPm.
#
# One container replaces Cachet's docker image (nginx + php-fpm under
# supervisord, plus the scheduler/queue workers): ePHPm serves public/ and
# runs PHP; the scheduler and the queue worker are separate services in
# compose.yml running the same image.
#
# Build args:
#   EPHPM_TAG       ephpm/ephpm image tag (default v0.11.3-php8.5)
#   CACHET_REF      cachethq/cachet commit to bake in. Cachet 3 has no
#                   tagged release yet; this pins the 3.x branch head the
#                   recipe was tested on (its composer.lock pins cachethq/core).

ARG EPHPM_TAG=v0.11.3-php8.5
ARG CACHET_REF=40bd0819ee46ee7094c336a1240a2a7a1291ccb8

# ── Stage 1: fetch the source ────────────────────────────────────────────────
FROM docker.io/library/alpine:3.20 AS src
ARG CACHET_REF
RUN apk add --no-cache curl tar
RUN mkdir /src \
    && curl -fsSL "https://github.com/cachethq/cachet/archive/${CACHET_REF}.tar.gz" \
       | tar xz --strip-components=1 -C /src \
    && rm -rf /src/tests /src/.github

# ── Stage 2: PHP dependencies ────────────────────────────────────────────────
FROM docker.io/library/composer:2 AS vendor
WORKDIR /app
COPY --from=src /src /app
# --no-scripts: package:discover and the asset publishing run below on the
# embedded PHP instead of the composer image's PHP.
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
    # composer's post-autoload-dump and post-update-cmd scripts, on the PHP
    # that will run the app: package discovery, then Cachet's and
    # Filament's compiled assets published into public/
    && cp .env.example .env \
    && ephpm php artisan package:discover --ansi \
    && ephpm php artisan vendor:publish --tag=laravel-assets --ansi --force \
    && ephpm php artisan vendor:publish --tag=cachet-assets --ansi --force \
    && ephpm php artisan filament:assets --ansi \
    && rm .env \
    # public/storage -> storage/app/public (uploaded logos)
    && ln -sfn /app/storage/app/public /app/public/storage \
    # pristine copy, used by entrypoint.sh to seed an empty storage volume
    && mkdir -p /usr/local/share/cachet \
    && cp -a /app/storage /usr/local/share/cachet/storage

VOLUME ["/app/storage"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
