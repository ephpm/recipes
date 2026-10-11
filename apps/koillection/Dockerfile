# Koillection on ePHPm.
#
# One container replaces the official koillection/koillection image, which is
# FrankenPHP (Caddy + a persistent PHP worker): ePHPm serves public/ and runs
# PHP in per-request mode; the Symfony front-controller rewrite comes from
# ephpm.toml.
#
# Build args:
#   EPHPM_TAG           ephpm/ephpm image tag (default v0.11.3-php8.5 — Koillection 1.8 needs PHP 8.5)
#   KOILLECTION_VERSION Koillection release tag to build (default 1.8.4)

ARG EPHPM_TAG=v0.11.3-php8.5
ARG KOILLECTION_VERSION=1.8.4

# ── Stage 1: source + PHP dependencies ───────────────────────────────────────
# No dist archive is published; the tag's tree is fetched and Composer runs
# with platform checks off (the composer image's PHP is older than 8.5 — the
# code only ever runs on the embedded PHP below).
FROM docker.io/library/composer:2 AS deps
ARG KOILLECTION_VERSION
RUN curl -fsSL "https://github.com/benjaminjonard/koillection/archive/refs/tags/${KOILLECTION_VERSION}.tar.gz" \
      | tar xz -C /tmp \
    && rm -rf /src && mv "/tmp/koillection-${KOILLECTION_VERSION}" /src
WORKDIR /src
RUN composer install --no-dev --no-scripts --no-interaction --no-progress \
        --prefer-dist --classmap-authoritative --ignore-platform-reqs \
    && rm -rf tests .github docker Dockerfile Dockerfile.dev docker-compose.dist.yml

# ── Stage 2: dump the JS translation catalogues on the embedded PHP ──────────
# (what the official image does before its yarn build)
FROM docker.io/ephpm/ephpm:${EPHPM_TAG} AS translations
COPY --from=deps /src /app
WORKDIR /app
# (composer.json sets runtime.dotenv_overload, so .env files win over real
# environment variables — hence a throwaway .env.local rather than env vars)
RUN printf 'APP_ENV=prod\nAPP_DEBUG=0\nAPP_SECRET=build\nDB_DRIVER=pdo_pgsql\nDB_NAME=x\nDB_HOST=127.0.0.1\nDB_PORT=5432\nDB_USER=x\nDB_PASSWORD=x\nDB_VERSION=16\n' > .env.local \
    && ephpm php -d memory_limit=-1 bin/console app:translations:dump --no-interaction \
    && rm -f .env.local && rm -rf var/cache/*

# ── Stage 3: frontend build ──────────────────────────────────────────────────
FROM docker.io/library/node:22-bookworm AS frontend
WORKDIR /app/assets
COPY --from=deps /src/assets /app/assets
COPY --from=translations /app/assets/js/translations /app/assets/js/translations
RUN mkdir -p /app/public/build && corepack enable && yarn install && yarn build

# ── Stage 4: APCu from the ePHPm extension catalog ───────────────────────────
# Koillection requires APCu (its Twig layer reads an APCu-backed cache pool).
# The catalog tag must match the image's PHP version (8.5.7 for v0.11.3-php8.5).
FROM docker.io/library/alpine:3.20 AS ext
ARG EPHPM_EXT_VERSION=8.5.7
RUN apk add --no-cache curl tar \
    && mkdir -p /opt/ephpm-ext \
    && curl -fsSL "https://github.com/ephpm/php-sdk/releases/download/ext-${EPHPM_EXT_VERSION}/ephpm-ext-${EPHPM_EXT_VERSION}-linux-x86_64-gnu.tar.gz" \
       | tar xz -C /opt/ephpm-ext

# ── Stage 5: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}
COPY --from=ext /opt/ephpm-ext/apcu.so /opt/ephpm-ext/apcu.so

# Same location as the official image (/app/public is the project root there).
COPY --from=translations /app /app/public
COPY --from=frontend /app/public/build /app/public/public/build
COPY ephpm.toml /etc/ephpm/
COPY koillection /usr/local/bin/koillection
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
WORKDIR /app/public
RUN chmod +x /usr/local/bin/koillection /usr/local/bin/entrypoint.sh \
    && mkdir -p /var/lib/ephpm /var/lib/koillection var/cache var/log var/share public/uploads \
    # pristine copy, used by entrypoint.sh to seed an empty uploads volume
    && cp -a public/uploads /usr/local/share/koillection-uploads \
    && rm -rf var/cache/*

VOLUME ["/app/public/public/uploads", "/var/lib/koillection"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
