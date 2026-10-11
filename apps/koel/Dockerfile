# Koel on ePHPm.
#
# One container replaces the official phanan/koel image (Apache + mod_php +
# cron): ePHPm serves public/, runs PHP and streams the music itself.
#
# Build args:
#   EPHPM_TAG      ephpm/ephpm image tag (default v0.11.3-php8.5)
#   KOEL_VERSION   Koel release to bake in (default v9.15.0)
#
# The release tarball on GitHub ships vendor/ and the built front-end in
# public/build (it is what the official image unpacks too), so no Composer
# or Node stage is needed.

ARG EPHPM_TAG=v0.11.3-php8.5
ARG KOEL_VERSION=v9.15.0

# ── Stage 1: fetch the release ───────────────────────────────────────────────
FROM docker.io/library/alpine:3.20 AS src
ARG KOEL_VERSION
RUN apk add --no-cache curl tar
RUN mkdir /src \
    && curl -fsSL "https://github.com/koel/koel/releases/download/${KOEL_VERSION}/koel-${KOEL_VERSION}.tar.gz" \
       | tar xz --strip-components=1 -C /src \
    # the same development leftovers the official Dockerfile removes
    && cd /src \
    && rm -rf .cursor .junie .vscode .github .vite-hooks api-docs docs scripts tests \
       resources/artifacts nginx.conf.example Caddyfile.example .htaccess.example \
       package.json pnpm-lock.yaml phpstan.neon.dist phpunit.xml.dist vite.config.ts \
       vite.config.sw.js tailwind.config.js postcss.config.cjs commitlint.config.js \
       mago.toml boost.json .mcp.json AGENTS.md CLAUDE.md CODE_OF_CONDUCT.md README.md

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
    && mkdir -p /music /app/storage/search-indexes /app/storage/app/public/images \
    && ln -sfn ../storage/app/public /app/public/storage \
    # pristine copy, used by entrypoint.sh to seed an empty storage volume
    && mkdir -p /usr/local/share/koel \
    && cp -a /app/storage /usr/local/share/koel/storage

VOLUME ["/music", "/app/storage"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
