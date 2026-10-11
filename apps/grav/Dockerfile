# Grav on ePHPm.
#
# One container replaces Apache/nginx + php-fpm (the linuxserver/grav image):
# ePHPm serves the files and runs PHP. Grav is flat-file — no database.
#
# Build args:
#   EPHPM_TAG     ephpm/ephpm image tag (default v0.11.3-php8.5)
#   GRAV_VERSION  Grav release (default 2.2.6); the "grav-admin" package,
#                 which bundles the admin2 panel and the API plugin

ARG EPHPM_TAG=v0.11.3-php8.5
ARG GRAV_VERSION=2.2.6

# ── Stage 1: the release package (vendor/ included) ──────────────────────────
FROM docker.io/library/alpine:3.20 AS src
ARG GRAV_VERSION
RUN apk add --no-cache curl unzip
RUN curl -fsSL -o /grav.zip "https://github.com/getgrav/grav/releases/download/${GRAV_VERSION}/grav-admin-v${GRAV_VERSION}.zip" \
    && unzip -q /grav.zip -d /tmp/grav && mv /tmp/grav/grav-admin /src \
    && rm -rf /src/webserver-configs /src/tests /src/.htaccess /src/now.json

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

COPY --from=src /src /var/www/html
COPY ephpm.toml /etc/ephpm/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
# `php` on PATH: Grav's CLI tools (bin/gpm self-upgrade, bin/plugin) may
# re-invoke PHP, and PHP_BINARY is `ephpm` here.
RUN printf '#!/bin/sh\nexec ephpm php "$@"\n' > /usr/local/bin/php && chmod +x /usr/local/bin/php \
    && chmod +x /usr/local/bin/entrypoint.sh \
    && mkdir -p /var/lib/ephpm \
    # pristine copy of user/ (config, pages, plugins, themes), used by
    # entrypoint.sh to seed an empty volume
    && mkdir -p /usr/local/share/grav \
    && cp -a /var/www/html/user /usr/local/share/grav/user

WORKDIR /var/www/html
VOLUME ["/var/www/html/user", "/var/www/html/backup"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
