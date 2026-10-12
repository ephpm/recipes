# Piwigo on ePHPm.
#
# One container replaces Apache/nginx + php-fpm (the linuxserver/piwigo
# image): ePHPm serves the gallery and runs PHP. Piwigo has no Composer
# dependencies and no build step, so the image is the release tag's tree.
#
# ePHPm's GD has no JPEG/WebP support (issues/koel.md), so the image adds
# Debian's ImageMagick; Piwigo picks it up as its `ext_imagick` graphics
# library for thumbnails and resizing (it shells out to `convert`).
#
# Build args:
#   EPHPM_TAG        ephpm/ephpm image tag (default v0.11.3-php8.5)
#   PIWIGO_VERSION   Piwigo release tag to bake in (default 16.4.0)

ARG EPHPM_TAG=v0.11.3-php8.5
ARG PIWIGO_VERSION=16.4.0

# ── Stage 1: the release source ──────────────────────────────────────────────
FROM docker.io/library/alpine:3.20 AS src
ARG PIWIGO_VERSION
RUN apk add --no-cache curl tar
RUN mkdir -p /src \
    && curl -fsSL "https://github.com/Piwigo/Piwigo/archive/refs/tags/${PIWIGO_VERSION}.tar.gz" \
       | tar xz --strip-components=1 -C /src \
    && rm -rf /src/.github /src/tools /src/doc /src/docs

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

RUN apt-get update \
    && apt-get install -y --no-install-recommends imagemagick \
    && rm -rf /var/lib/apt/lists/*

# The base image ships ePHPm's own test fixtures in /var/www/html (phpinfo()
# among them, see issues/joomla.md); start from an empty directory.
RUN rm -rf /var/www/html
COPY --from=src /src /var/www/html
COPY php /usr/local/bin/php
COPY ephpm.toml /etc/ephpm/ephpm.toml
COPY entrypoint.sh install.php /usr/local/share/piwigo/
RUN chmod +x /usr/local/bin/php /usr/local/share/piwigo/entrypoint.sh \
    # pristine copies, used by entrypoint.sh to seed empty volumes
    && cp -a /var/www/html/local /var/www/html/galleries /usr/local/share/piwigo/ \
    && mkdir -p /var/www/html/_data /var/www/html/upload

WORKDIR /var/www/html
VOLUME ["/var/www/html/local", "/var/www/html/_data", "/var/www/html/upload", "/var/www/html/galleries"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/share/piwigo/entrypoint.sh"]
