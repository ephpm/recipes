# Invoice Ninja (v5) on ePHPm.
#
# One container replaces the official invoiceninja/invoiceninja image's
# php-fpm plus its nginx companion container: ePHPm serves public/ and runs
# PHP.
#
# Build args:
#   EPHPM_TAG      ephpm/ephpm image tag (default v0.11.3-php8.5)
#   NINJA_VERSION  Invoice Ninja release to bake in (default v5.13.47)
#
# The release tarball on GitHub ships vendor/ and the built UI (public/build
# and the React/Flutter bundles), so no Composer or Node stage is needed.

ARG EPHPM_TAG=v0.11.3-php8.5
ARG NINJA_VERSION=v5.13.47

# ── Stage 1: fetch the release ───────────────────────────────────────────────
FROM docker.io/library/alpine:3.20 AS src
ARG NINJA_VERSION
RUN apk add --no-cache curl tar
RUN mkdir /src \
    && curl -fsSL "https://github.com/invoiceninja/invoiceninja/releases/download/${NINJA_VERSION}/invoiceninja.tar.gz" \
       | tar xz -C /src \
    && rm -rf /src/tests /src/.github /src/openapi /src/playwright.config.ts \
       /src/package.json /src/package-lock.json /src/vite.config.ts /src/vite.config.ts.react

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

# Invoice Ninja ships a Laravel schema dump (database/schema/mysql-schema.sql)
# that `artisan migrate` loads through the `mysql` CLI on a fresh database.
RUN apt-get update \
    && apt-get install -y --no-install-recommends mariadb-client \
    && rm -rf /var/lib/apt/lists/*

COPY --from=src /src /app
COPY ephpm.toml /etc/ephpm/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
# `php` on PATH: Laravel's scheduler and tools that re-invoke PHP look for
# a `php` binary (PHP_BINARY is `ephpm` here), so give them `ephpm php`.
RUN printf '#!/bin/sh\nexec ephpm php "$@"\n' > /usr/local/bin/php && chmod +x /usr/local/bin/php
WORKDIR /app
RUN chmod +x /usr/local/bin/entrypoint.sh \
    # pristine copies, used by entrypoint.sh to seed empty volumes
    && mkdir -p /usr/local/share/invoiceninja \
    && cp -a /app/storage /usr/local/share/invoiceninja/storage \
    && cp -a /app/public/storage /usr/local/share/invoiceninja/public-storage 2>/dev/null || mkdir -p /usr/local/share/invoiceninja/public-storage

VOLUME ["/app/storage", "/app/public/storage"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
