# FreshRSS on ePHPm.
#
# One container replaces Apache + mod_php (the freshrss/freshrss image) and
# cron: ePHPm serves p/ and runs PHP, the feed refresher runs on the embedded
# PHP CLI, and PHP sessions live in ePHPm's in-process KV store.
#
# Build args:
#   EPHPM_TAG         ephpm/ephpm image tag (default v0.11.3-php8.5)
#   FRESHRSS_VERSION  FreshRSS release to bake in (default 1.30.1)

ARG EPHPM_TAG=v0.11.3-php8.5
ARG FRESHRSS_VERSION=1.30.1

# ── Stage 1: fetch the release (no Composer step: FreshRSS vendors lib/) ─────
FROM docker.io/library/alpine:3.20 AS src
ARG FRESHRSS_VERSION
RUN apk add --no-cache curl tar
RUN mkdir -p /src \
    && curl -fsSL "https://github.com/FreshRSS/FreshRSS/archive/refs/tags/${FRESHRSS_VERSION}.tar.gz" \
       | tar xz --strip-components=1 -C /src \
    # development-only material
    && cd /src && rm -rf tests docs Docker .github Makefile AGENTS.md CONTRIBUTING.md \
       phpcs.xml phpstan*.neon phpunit.xml eslint.config.js svgo.config.mjs package.json package-lock.json \
    # Like the official image: the image is updated, not the app from inside the UI.
    && sed -r -i "\\#disable_update#s#^.*#\t'disable_update' => true,#" config.default.php

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

COPY --from=src /src /var/www/FreshRSS
COPY php /usr/local/bin/php
COPY ephpm.toml dns-polyfill.php /etc/ephpm/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/php /usr/local/bin/entrypoint.sh /var/www/FreshRSS/cli/*.php \
    && mkdir -p /var/lib/ephpm /run/ephpm /var/www/FreshRSS/extensions

WORKDIR /var/www/FreshRSS
VOLUME ["/var/www/FreshRSS/data", "/var/www/FreshRSS/extensions"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
