# ProjectSend 2 on ePHPm.
#
# One container replaces the official projectsend/projectsend image's
# nginx + php-fpm (+ the queue workers and the scheduler it runs next to
# them): ePHPm serves public/ and runs PHP; the queue worker and the
# scheduler are sidecars from the same image.
#
# Build args:
#   EPHPM_TAG             ephpm/ephpm image tag (default v0.11.3-php8.5)
#   PROJECTSEND_VERSION   release (the zip ships vendor/ and the built front-end)

ARG EPHPM_TAG=v0.11.3-php8.5
ARG PROJECTSEND_VERSION=2.7.0

# ── Stage 1: the release zip ─────────────────────────────────────────────────
FROM docker.io/library/alpine:3.20 AS src
ARG PROJECTSEND_VERSION
RUN apk add --no-cache curl unzip
RUN curl -fsSL -o /tmp/ps.zip \
        "https://github.com/projectsend/projectsend/releases/download/v${PROJECTSEND_VERSION}/projectsend-${PROJECTSEND_VERSION}.zip" \
    && mkdir /src && unzip -q /tmp/ps.zip -d /src && rm /tmp/ps.zip \
    && rm -rf /src/docs /src/update.sh

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

COPY --from=src /src /app
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
    && mkdir -p /usr/local/share/projectsend && cp -a storage /usr/local/share/projectsend/storage

ENV APP_ENV=production \
    APP_DEBUG=false \
    LOG_CHANNEL=stderr \
    PROJECTSEND_FILE_DELIVERY=php

VOLUME ["/app/storage"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
