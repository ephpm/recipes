# GLPI on ePHPm.
#
# One container replaces the official glpi/glpi image's Apache + mod_php +
# supervisord: ePHPm serves public/ and routes every other URL to GLPI's
# router (public/index.php); GLPI's cron runs as a sidecar from the same
# image, the way the official image's `glpi-cron` program does.
#
# Build args:
#   EPHPM_TAG      ephpm/ephpm image tag (default v0.11.3-php8.5)
#   GLPI_VERSION   GLPI release to bake in (default 12.0.0)

ARG EPHPM_TAG=v0.11.3-php8.5
ARG GLPI_VERSION=12.0.0

# ── Stage 1: the release tarball (vendor/ and built assets included) ─────────
FROM docker.io/library/alpine:3.20 AS src
ARG GLPI_VERSION
RUN apk add --no-cache curl tar
RUN mkdir -p /src \
    && curl -fsSL "https://github.com/glpi-project/glpi/releases/download/${GLPI_VERSION}/glpi-${GLPI_VERSION}.tgz" \
       | tar xz --strip-components=1 -C /src

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

COPY --from=src /src /var/www/glpi
COPY ephpm.toml /etc/ephpm/ephpm.toml
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
# `php` on PATH: GLPI's own tooling (and its docs) call `php bin/console`.
RUN printf '#!/bin/sh\nexec ephpm php "$@"\n' > /usr/local/bin/php \
    && chmod +x /usr/local/bin/php /usr/local/bin/entrypoint.sh \
    && mkdir -p /var/glpi /var/lib/ephpm \
    # GLPI's CLI and cron refuse to run as root (official image: USER www-data);
    # a fresh named volume inherits this ownership
    && chown www-data:www-data /var/glpi /var/lib/ephpm

# The official image's layout: configuration, files, logs and marketplace
# plugins live in the /var/glpi volume, the code stays in the image.
ENV GLPI_INSTALL_MODE=DOCKER \
    GLPI_CONFIG_DIR=/var/glpi/config \
    GLPI_MARKETPLACE_DIR=/var/glpi/marketplace \
    GLPI_VAR_DIR=/var/glpi/files \
    GLPI_LOG_DIR=/var/glpi/logs \
    GLPI_SKIP_AUTOINSTALL=false \
    GLPI_SKIP_AUTOUPDATE=false

USER www-data
WORKDIR /var/www/glpi
VOLUME ["/var/glpi"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
