# Akaunting on ePHPm.
#
# Akaunting publishes no official container image; this replaces the usual
# nginx/apache + php-fpm host with ePHPm serving public/ and running PHP.
#
# Build args:
#   EPHPM_TAG           ephpm/ephpm image tag (default v0.11.3-php8.3 —
#                       Akaunting 3.2 is Laravel 10 and declares php ^8.1)
#   AKAUNTING_VERSION   Akaunting release to bake in (default 3.2.4)
#
# The "Stable" release zip ships vendor/ and the compiled assets, so no
# Composer or Node stage is needed.

ARG EPHPM_TAG=v0.11.3-php8.3
ARG AKAUNTING_VERSION=3.2.4

# ── Stage 1: fetch the release ───────────────────────────────────────────────
FROM docker.io/library/alpine:3.20 AS src
ARG AKAUNTING_VERSION
RUN apk add --no-cache curl unzip
RUN mkdir /src \
    && curl -fsSL -o /tmp/akaunting.zip \
       "https://github.com/akaunting/akaunting/releases/download/${AKAUNTING_VERSION}/Akaunting_${AKAUNTING_VERSION}-Stable.zip" \
    && unzip -q /tmp/akaunting.zip -d /src \
    && rm -f /tmp/akaunting.zip /src/nginx.example.com.conf /src/web.config /src/LocalValetDriver.php

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
    && mkdir -p /usr/local/share/akaunting \
    && cp -a /app/storage /usr/local/share/akaunting/storage

VOLUME ["/app/storage"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
