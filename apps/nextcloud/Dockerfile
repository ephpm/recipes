# Nextcloud on ePHPm.
#
# One container replaces the official nextcloud:apache image (Apache +
# mod_php) or the nextcloud:fpm image + an nginx container: ePHPm serves the
# files and runs PHP. A background-jobs sidecar from the same image replaces
# the `cron` container of upstream's examples.
#
# Build args:
#   EPHPM_TAG          ephpm/ephpm image tag (default v0.11.3-php8.5)
#   NEXTCLOUD_VERSION  Nextcloud server release (default 35.0.1; 35 is the
#                      first major that accepts PHP 8.5)
#   EPHPM_EXT_VERSION  ePHPm extension catalog tag, must match the image's PHP
#                      (8.5.7 for v0.11.3-php8.5) — provides APCu

ARG EPHPM_TAG=v0.11.3-php8.5
ARG NEXTCLOUD_VERSION=35.0.1
ARG EPHPM_EXT_VERSION=8.5.7

# ── Stage 1: the release tarball (vendor and built assets included) ──────────
FROM docker.io/library/alpine:3.20 AS src
ARG NEXTCLOUD_VERSION
ARG EPHPM_EXT_VERSION
RUN apk add --no-cache curl tar bzip2
WORKDIR /dl
# (the .sha256 file lists the tarball and the .metadata file; check the tarball's line)
RUN curl -fsSL "https://download.nextcloud.com/server/releases/nextcloud-${NEXTCLOUD_VERSION}.tar.bz2" -o "nextcloud-${NEXTCLOUD_VERSION}.tar.bz2" \
    && curl -fsSL "https://download.nextcloud.com/server/releases/nextcloud-${NEXTCLOUD_VERSION}.tar.bz2.sha256" \
       | grep " nextcloud-${NEXTCLOUD_VERSION}.tar.bz2\$" | sha256sum -c - \
    && mkdir /src && tar xjf "nextcloud-${NEXTCLOUD_VERSION}.tar.bz2" --strip-components=1 -C /src \
    && rm "nextcloud-${NEXTCLOUD_VERSION}.tar.bz2"
# APCu (memcache.local) from the ePHPm extension catalog (ZTS builds).
RUN mkdir -p /opt/ephpm-ext \
    && curl -fsSL "https://github.com/ephpm/php-sdk/releases/download/ext-${EPHPM_EXT_VERSION}/ephpm-ext-${EPHPM_EXT_VERSION}-linux-x86_64-gnu.tar.gz" \
       | tar xz -C /opt/ephpm-ext ./apcu.so

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

COPY --from=src /src /var/www/html
COPY --from=src /opt/ephpm-ext/apcu.so /opt/ephpm-ext/apcu.so
COPY ephpm.toml /etc/ephpm/
COPY ephpm-pathinfo.php /usr/local/share/nextcloud/ephpm-pathinfo.php
COPY ephpm.config.php /usr/local/share/nextcloud/ephpm.config.php
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
# `php` on PATH for tools that re-invoke PHP (PHP_BINARY is `ephpm` here).
RUN printf '#!/bin/sh\nexec ephpm php "$@"\n' > /usr/local/bin/php && chmod +x /usr/local/bin/php \
    && printf '#!/bin/sh\ncd /var/www/html && exec ephpm php occ "$@"\n' > /usr/local/bin/occ && chmod +x /usr/local/bin/occ \
    && chmod +x /usr/local/bin/entrypoint.sh \
    && mkdir -p /var/lib/ephpm /var/www/html/data /var/www/html/custom_apps \
    # pristine copy of config/ (CAN_INSTALL etc.), used to seed an empty volume
    && cp -a /var/www/html/config /usr/local/share/nextcloud/config

WORKDIR /var/www/html
VOLUME ["/var/www/html/config", "/var/www/html/data", "/var/www/html/custom_apps"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
