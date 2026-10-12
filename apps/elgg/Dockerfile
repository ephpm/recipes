# Elgg on ePHPm.
#
# One container replaces the Apache/nginx + php-fpm setup Elgg documents:
# ePHPm serves the project root (index.php front controller, the nginx.dist
# try_files rules as [server] fallback) and runs PHP; elgg-cli (install,
# cron, upgrade) runs on the embedded PHP.
#
# Build args:
#   EPHPM_TAG      ephpm/ephpm image tag (default v0.11.3-php8.5)
#   ELGG_VERSION   Elgg release (default 7.1.1)

ARG EPHPM_TAG=v0.11.3-php8.5
ARG ELGG_VERSION=7.1.1

# ── Stage 1: the release package (the starter project with vendor/) ────────
FROM docker.io/library/alpine:3.20 AS src
ARG ELGG_VERSION
RUN apk add --no-cache curl unzip
RUN curl -fsSL -o /elgg.zip "https://github.com/Elgg/Elgg/releases/download/${ELGG_VERSION}/elgg-${ELGG_VERSION}.zip" \
    && unzip -q /elgg.zip -d / \
    && mv "/elgg-${ELGG_VERSION}" /src \
    && rm -f /src/phpunit.xml.dist

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

COPY --from=src /src /var/www/elgg
COPY ephpm.toml /etc/ephpm/ephpm.toml
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY elgg-cli /usr/local/bin/elgg-cli
# `php` on PATH: elgg-cli's shebang is `#!/usr/bin/env php`.
RUN printf '#!/bin/sh\nexec ephpm php "$@"\n' > /usr/local/bin/php \
    && chmod +x /usr/local/bin/php /usr/local/bin/entrypoint.sh /usr/local/bin/elgg-cli \
    && mkdir -p /var/lib/elgg/data

WORKDIR /var/www/elgg
# elgg-config/ holds settings.php (written by the installer); the data
# directory holds uploads, caches and the system log.
VOLUME ["/var/www/elgg/elgg-config", "/var/lib/elgg/data"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
