# BookStack on ePHPm.
#
# One container replaces the linuxserver/bookstack image's nginx + php-fpm
# (+ a Redis service for cache/sessions): ePHPm serves public/, runs PHP and
# can provide the Redis-compatible KV store for cache/sessions.
#
# Build args:
#   EPHPM_TAG           ephpm/ephpm image tag (default v0.11.3-php8.5)
#   BOOKSTACK_VERSION   BookStack release tag to bake in (default v26.09.1)
#
# BookStack commits its built assets (public/dist), so only a Composer stage
# is needed — no Node build.

ARG EPHPM_TAG=v0.11.3-php8.5
ARG BOOKSTACK_VERSION=v26.09.1

# ── Stage 1: fetch the release source ────────────────────────────────────────
FROM docker.io/library/alpine:3.20 AS src
ARG BOOKSTACK_VERSION
RUN apk add --no-cache curl tar
RUN mkdir /src \
    && curl -fsSL "https://github.com/BookStackApp/BookStack/archive/refs/tags/${BOOKSTACK_VERSION}.tar.gz" \
       | tar xz --strip-components=1 -C /src \
    && rm -rf /src/tests /src/dev /src/.github

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
WORKDIR /app
RUN chmod +x /usr/local/bin/entrypoint.sh \
    && mkdir -p /var/lib/ephpm \
    # the composer script skipped above, on the PHP that will run the app
    && ephpm php artisan package:discover --ansi \
    # pristine copies, used by entrypoint.sh to seed empty volumes
    && mkdir -p /usr/local/share/bookstack \
    && cp -a /app/storage /usr/local/share/bookstack/storage \
    && cp -a /app/public/uploads /usr/local/share/bookstack/uploads \
    && cp -a /app/themes /usr/local/share/bookstack/themes

VOLUME ["/app/storage", "/app/public/uploads"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
