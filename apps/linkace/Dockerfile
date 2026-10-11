# LinkAce on ePHPm.
#
# One container replaces the official image's Caddy + php-fpm (+ Redis for
# cache/sessions): ePHPm serves public/, runs PHP and can provide the
# Redis-compatible KV store for cache/sessions.
#
# Build args:
#   EPHPM_TAG         ephpm/ephpm image tag (default v0.11.3-php8.5)
#   LINKACE_VERSION   LinkAce release to bake in (default 2.6.2)
#
# The release zip on GitHub ships vendor/ (composer install --no-dev already
# run) and the built Vite assets in public/build, so no Composer or Node
# stage is needed.

ARG EPHPM_TAG=v0.11.3-php8.5
ARG LINKACE_VERSION=2.6.2

# ── Stage 1: fetch the release ───────────────────────────────────────────────
FROM docker.io/library/alpine:3.20 AS src
ARG LINKACE_VERSION
RUN apk add --no-cache curl unzip
RUN mkdir /src \
    && curl -fsSL -o /tmp/linkace.zip \
       "https://github.com/Kovah/LinkAce/releases/download/v${LINKACE_VERSION}/linkace-v${LINKACE_VERSION}.zip" \
    && unzip -q /tmp/linkace.zip -d /src \
    && rm -rf /tmp/linkace.zip \
       /src/tests /src/deploy /src/.deploystack /src/docker-compose.yml \
       /src/docker-compose.production.yml /src/.env.* /src/resources/assets \
       /src/storage/debugbar

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

# LinkAce ships a pruned migration set plus a schema dump
# (database/schema/mysql-schema.dump); Laravel loads the dump through the
# `mysql` CLI, so the client is needed exactly as in the official base image.
RUN apt-get update \
    && apt-get install -y --no-install-recommends mariadb-client \
    && rm -rf /var/lib/apt/lists/*

COPY --from=src /src /app
COPY env.template /usr/local/share/linkace/env.template
COPY ephpm.toml /etc/ephpm/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh \
    && mkdir -p /var/lib/ephpm \
    # pristine copy of storage/, used by entrypoint.sh to seed an empty volume
    && cp -a /app/storage /usr/local/share/linkace/storage

WORKDIR /app
VOLUME ["/app/storage"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
