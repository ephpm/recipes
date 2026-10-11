# Heimdall on ePHPm.
#
# One container replaces the linuxserver/heimdall image (nginx + php-fpm +
# s6): ePHPm serves public/ and runs PHP; Heimdall keeps its SQLite database
# in the data volume.
#
# Build args:
#   EPHPM_TAG          ephpm/ephpm image tag (default v0.11.3-php8.5)
#   HEIMDALL_VERSION   Heimdall release tag (default v2.8.3)
#
# Heimdall commits vendor/ and its built assets, so no Composer/Node stage.

ARG EPHPM_TAG=v0.11.3-php8.5
ARG HEIMDALL_VERSION=v2.8.3

FROM docker.io/library/alpine:3.20 AS src
ARG HEIMDALL_VERSION
RUN apk add --no-cache curl tar
RUN mkdir /src \
    && curl -fsSL "https://github.com/linuxserver/Heimdall/archive/refs/tags/${HEIMDALL_VERSION}.tar.gz" \
       | tar xz --strip-components=1 -C /src \
    && rm -rf /src/tests /src/docker /src/.github /src/.vscode /src/xdebug.ini

FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

COPY --from=src /src /app
COPY ephpm.toml /etc/ephpm/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
# `php` on PATH for tools that re-invoke PHP (PHP_BINARY is `ephpm` here).
RUN printf '#!/bin/sh\nexec ephpm php "$@"\n' > /usr/local/bin/php && chmod +x /usr/local/bin/php \
    && chmod +x /usr/local/bin/entrypoint.sh \
    && mkdir -p /var/lib/ephpm /data \
    # .env and the SQLite database live in the data volume
    && ln -s /data/.env /app/.env \
    && ln -s /data/app.sqlite /app/database/app.sqlite \
    # uploaded icons (storage/app/public) are served from public/storage
    && ln -s /app/storage/app/public /app/public/storage \
    # pristine copy of storage/, used by entrypoint.sh to seed an empty volume
    && mkdir -p /usr/local/share/heimdall \
    && cp -a /app/storage /usr/local/share/heimdall/storage

WORKDIR /app
VOLUME ["/data", "/app/storage"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
