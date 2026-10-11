# Monica (v4) on ePHPm.
#
# One container replaces the official monica:4-apache image (Apache +
# mod_php) and its busybox-cron sidecar: ePHPm serves public/ and runs PHP;
# the scheduler is a second container from the same image.
#
# Build args:
#   EPHPM_TAG        ephpm/ephpm image tag (default v0.11.3-php8.3 — Monica 4
#                    is Laravel 9 and declares php ^8.1; the official image
#                    runs PHP 8.2)
#   MONICA_VERSION   Monica release to bake in (default v4.1.2, the latest 4.x)
#
# The release tarball on GitHub ships vendor/ and the compiled assets
# (public/js, public/css), so no Composer or Node stage is needed.

ARG EPHPM_TAG=v0.11.3-php8.3
ARG MONICA_VERSION=v4.1.2

# ── Stage 1: fetch the release ───────────────────────────────────────────────
FROM docker.io/library/alpine:3.20 AS src
ARG MONICA_VERSION
RUN apk add --no-cache curl tar bzip2
RUN mkdir /src \
    && curl -fsSL "https://github.com/monicahq/monica/releases/download/${MONICA_VERSION}/monica-${MONICA_VERSION}.tar.bz2" \
       | tar xj --strip-components=1 -C /src \
    && rm -rf /src/tests /src/.github /src/docs /src/nginx_app.conf /src/server.php

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
    && mkdir -p /usr/local/share/monica \
    && cp -a /app/storage /usr/local/share/monica/storage

VOLUME ["/app/storage"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
