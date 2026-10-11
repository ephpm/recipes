# UVdesk Community Helpdesk on ePHPm.
#
# One container replaces the official uvdesk/community-skeleton image
# (Ubuntu + apache2 + mod_php 8.1, with a MySQL server inside the same
# container): ePHPm serves public/ and runs PHP; MariaDB is its own service.
#
# Build args:
#   EPHPM_TAG       ephpm/ephpm image tag (default v0.11.3-php8.3 — UVdesk
#                   1.1 is Symfony 5.4, whose last tested PHP is 8.3)
#   UVDESK_VERSION  community-skeleton release (default v1.1.8)

ARG EPHPM_TAG=v0.11.3-php8.3
ARG UVDESK_VERSION=v1.1.8

# ── Stage 1: composer create-project (what the official Dockerfile's ─────────
#    `composer install` amounts to: Symfony Flex resolves the skeleton's
#    flex-require list and applies the recipes)
FROM docker.io/library/composer:2 AS build
ARG UVDESK_VERSION
RUN composer create-project "uvdesk/community-skeleton:${UVDESK_VERSION}" /app \
        --no-interaction --prefer-dist --ignore-platform-reqs --no-progress \
    && rm -rf /app/var/cache/* /app/var/log/* /app/.docker /app/Dockerfile /app/compose*.yaml

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

COPY --from=build /app /app
COPY ephpm.toml /etc/ephpm/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY uvdesk /usr/local/bin/uvdesk
WORKDIR /app
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/uvdesk \
    && mkdir -p /var/lib/ephpm \
    # pristine copy of the upload directory, used to seed an empty volume
    && mkdir -p /usr/local/share/uvdesk /app/public/assets \
    && cp -a /app/public/assets /usr/local/share/uvdesk/assets

ENV APP_ENV=prod APP_DEBUG=0
VOLUME ["/app/public/assets"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
