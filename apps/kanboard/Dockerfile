# Kanboard on ePHPm.
#
# One container replaces nginx + php-fpm + s6 + crond (the kanboard/kanboard
# image): ePHPm serves the files and runs PHP, and the daily cron job runs on
# the embedded PHP CLI from the entrypoint.
#
# Build args:
#   EPHPM_TAG         ephpm/ephpm image tag (default v0.11.3-php8.5)
#   KANBOARD_VERSION  Kanboard release to bake in (default v1.2.54)

ARG EPHPM_TAG=v0.11.3-php8.5
ARG KANBOARD_VERSION=v1.2.54

# ── Stage 1: the release tarball (vendor/ is committed; no Composer step) ────
FROM docker.io/library/alpine:3.20 AS src
ARG KANBOARD_VERSION
RUN apk add --no-cache curl tar
RUN mkdir -p /src \
    && curl -fsSL "https://github.com/kanboard/kanboard/archive/refs/tags/${KANBOARD_VERSION}.tar.gz" \
       | tar xz --strip-components=1 -C /src \
    && cd /src \
    && rm -rf docker docker-compose.*.yml CONTRIBUTING.md .github web.config \
    # the official Dockerfile does the same so the UI shows the version
    && echo "${KANBOARD_VERSION}" > app/version.txt

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

COPY --from=src /src /var/www/app
COPY php /usr/local/bin/php
COPY ephpm.toml /etc/ephpm/ephpm.toml
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/php /usr/local/bin/entrypoint.sh /var/www/app/cli \
    && mkdir -p /var/lib/ephpm /var/www/app/data /var/www/app/plugins

WORKDIR /var/www/app
VOLUME ["/var/www/app/data", "/var/www/app/plugins"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
