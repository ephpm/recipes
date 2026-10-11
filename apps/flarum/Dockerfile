# Flarum on ePHPm.
#
# One container replaces nginx + php-fpm (the mondedie/flarum and
# crazymax/flarum images): ePHPm serves public/ and runs PHP.
#
# Build args:
#   EPHPM_TAG       ephpm/ephpm image tag (default v0.11.3-php8.5)
#   FLARUM_VERSION  flarum/flarum skeleton version constraint (default ^2.0)
#
# Extensions are Composer packages: add `composer require <vendor/extension>`
# to the vendor stage and rebuild.

ARG EPHPM_TAG=v0.11.3-php8.5
ARG FLARUM_VERSION=^2.0

# ── Stage 1: the skeleton + dependencies ─────────────────────────────────────
FROM docker.io/library/composer:2 AS vendor
ARG FLARUM_VERSION
RUN composer create-project --no-interaction --prefer-dist --no-dev --no-scripts \
        --ignore-platform-reqs flarum/flarum /app "${FLARUM_VERSION}" \
    && cd /app && composer dump-autoload --optimize --no-dev --no-scripts

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

COPY --from=vendor /app /app
COPY ephpm.toml /etc/ephpm/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
# `php` on PATH for tools that re-invoke PHP (PHP_BINARY is `ephpm` here),
# and `flarum` for the console.
RUN printf '#!/bin/sh\nexec ephpm php "$@"\n' > /usr/local/bin/php && chmod +x /usr/local/bin/php \
    && printf '#!/bin/sh\ncd /app && exec ephpm php flarum "$@"\n' > /usr/local/bin/flarum && chmod +x /usr/local/bin/flarum \
    && chmod +x /usr/local/bin/entrypoint.sh \
    && mkdir -p /var/lib/ephpm /data \
    # pristine copies, used by entrypoint.sh to seed empty volumes
    && mkdir -p /usr/local/share/flarum \
    && cp -a /app/storage /usr/local/share/flarum/storage \
    && cp -a /app/public/assets /usr/local/share/flarum/assets \
    # config.php is written by the installer; it lives in the data volume
    && ln -s /data/config.php /app/config.php

WORKDIR /app
VOLUME ["/data", "/app/storage", "/app/public/assets"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
