# Joomla on ePHPm.
#
# One container replaces the official `joomla` image's Apache + mod_php:
# ePHPm serves the site and the administrator and runs PHP; Joomla's CLI
# installer (installation/joomla.php) and cli/joomla.php run on the
# embedded PHP.
#
# Build args:
#   EPHPM_TAG        ephpm/ephpm image tag (default v0.11.3-php8.5)
#   JOOMLA_VERSION   Joomla release to bake in (default 6.1.4)

ARG EPHPM_TAG=v0.11.3-php8.5
ARG JOOMLA_VERSION=6.1.4

# ── Stage 1: the full release package ────────────────────────────────────────
FROM docker.io/library/alpine:3.20 AS src
ARG JOOMLA_VERSION
RUN apk add --no-cache curl tar
RUN mkdir -p /src \
    && curl -fsSL "https://github.com/joomla/joomla-cms/releases/download/${JOOMLA_VERSION}/Joomla_${JOOMLA_VERSION}-Stable-Full_Package.tar.gz" \
       | tar xz -C /src \
    && rm -f /src/web.config.txt

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

# Like the official image: the release sits in /usr/src/joomla and is copied
# into the /var/www/html volume on first start (Joomla installs extensions,
# templates and updates into its own tree, so the whole tree is state).
COPY --from=src /src /usr/src/joomla
# The base image ships ePHPm's own test fixtures in /var/www/html (phpinfo()
# among them, see issues/joomla.md); the volume must start empty.
RUN rm -rf /var/www/html
COPY ephpm.toml /etc/ephpm/ephpm.toml
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
# `php` on PATH: `php cli/joomla.php ...` as documented.
RUN printf '#!/bin/sh\nexec ephpm php "$@"\n' > /usr/local/bin/php \
    && chmod +x /usr/local/bin/php /usr/local/bin/entrypoint.sh \
    && mkdir -p /var/www/html /var/lib/ephpm

WORKDIR /var/www/html
VOLUME ["/var/www/html"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
