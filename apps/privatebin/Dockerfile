# PrivateBin on ePHPm.
#
# One container replaces nginx + php-fpm + s6 (the privatebin/nginx-fpm-alpine
# image): ePHPm serves the static assets and runs index.php. PrivateBin is
# flat-file by default (pastes under /srv/data).
#
# Build args:
#   EPHPM_TAG           ephpm/ephpm image tag (default v0.11.3-php8.5)
#   PRIVATEBIN_VERSION  PrivateBin release to bake in (default 2.0.6)

ARG EPHPM_TAG=v0.11.3-php8.5
ARG PRIVATEBIN_VERSION=2.0.6

# ── Stage 1: the release (vendor/ is committed; no Composer step) ────────────
FROM docker.io/library/alpine:3.20 AS src
ARG PRIVATEBIN_VERSION
RUN apk add --no-cache curl tar
RUN mkdir -p /var/www /srv \
    && curl -fsSL "https://github.com/PrivateBin/PrivateBin/archive/refs/tags/${PRIVATEBIN_VERSION}.tar.gz" \
       | tar xz --strip-components=1 -C /var/www \
    && cd /var/www \
    && rm -rf *.md .github .gitignore composer.json composer.lock Procfile \
    # Same layout as the official image: code and config live OUTSIDE the web
    # root, index.php finds them through PATH.
    && mv bin cfg lib tpl vendor /srv \
    && mkdir -p /srv/data \
    && sed -i "s#define('PATH', '');#define('PATH', '/srv/');#" index.php \
    && grep -q "define('PATH', '/srv/');" index.php

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

COPY --from=src /var/www /var/www
COPY --from=src /srv /srv
COPY conf.php /srv/cfg/conf.php
COPY ephpm.toml /etc/ephpm/ephpm.toml
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /var/www
VOLUME ["/srv/data"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
