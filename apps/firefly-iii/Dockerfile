# Firefly III on ePHPm.
#
# One container replaces the official fireflyiii/core image (serversideup
# nginx + php-fpm, s6): ePHPm serves public/, runs PHP and can provide the
# Redis-compatible KV store for cache/sessions.
#
# Build args:
#   EPHPM_TAG         ephpm/ephpm image tag (default v0.11.3-php8.5)
#   FIREFLY_VERSION   Firefly III release to bake in (default v6.7.9)
#
# The release tarball on GitHub ships vendor/ and the built assets in
# public/build (it is what the official image unzips too), so no Composer
# or Node stage is needed.

ARG EPHPM_TAG=v0.11.3-php8.5
ARG FIREFLY_VERSION=v6.7.9

# ── Stage 1: fetch the release ───────────────────────────────────────────────
FROM docker.io/library/alpine:3.20 AS src
ARG FIREFLY_VERSION
RUN apk add --no-cache curl tar
RUN mkdir /src \
    && curl -fsSL "https://github.com/firefly-iii/firefly-iii/releases/download/${FIREFLY_VERSION}/FireflyIII-${FIREFLY_VERSION}.tar.gz" \
       | tar xz -C /src \
    && rm -rf /src/tests /src/.env.testing /src/nginx_app.conf /src/.htaccess /src/server.php

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

COPY --from=src /src /app
COPY ephpm.toml /etc/ephpm/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
# `php` on PATH: Laravel's scheduler and tools that re-invoke PHP look for
# a `php` binary (PHP_BINARY is `ephpm` here), so give them `ephpm php`.
RUN printf '#!/bin/sh\nexec ephpm php "$@"\n' > /usr/local/bin/php && chmod +x /usr/local/bin/php
WORKDIR /app
RUN chmod +x /usr/local/bin/entrypoint.sh \
    # pristine copy, used by entrypoint.sh to seed an empty storage volume
    && mkdir -p /usr/local/share/firefly-iii \
    && cp -a /app/storage /usr/local/share/firefly-iii/storage

VOLUME ["/app/storage"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
