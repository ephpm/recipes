# Fusio on ePHPm.
#
# One container replaces the official fusio/fusio image's Apache + mod_php
# (+ cron): ePHPm serves public/ and runs PHP; a `cron` sidecar from the
# same image runs `bin/fusio system:cronjob` every minute.
#
# Build args:
#   EPHPM_TAG              ephpm/ephpm image tag (default v0.11.3-php8.5)
#   FUSIO_VERSION          Fusio release (the zip ships vendor/)
#   FUSIO_APP_*            versions of the bundled web apps (same as the official image)

ARG EPHPM_TAG=v0.11.3-php8.5
ARG FUSIO_VERSION=7.2.0
ARG FUSIO_APP_BACKEND=7.2.0
ARG FUSIO_APP_DEVELOPER=7.2.1
ARG FUSIO_APP_ACCOUNT=2.4.0
ARG FUSIO_APP_REDOC=1.0.4

# ── Stage 1: the release + the backend/developer/account/redoc apps ──────────
FROM docker.io/library/alpine:3.20 AS src
ARG FUSIO_VERSION
ARG FUSIO_APP_BACKEND
ARG FUSIO_APP_DEVELOPER
ARG FUSIO_APP_ACCOUNT
ARG FUSIO_APP_REDOC
RUN apk add --no-cache curl unzip
RUN mkdir -p /src && cd /src \
    && curl -fsSL -o /tmp/fusio.zip "https://github.com/apioo/fusio/releases/download/v${FUSIO_VERSION}/fusio.zip" \
    && unzip -q /tmp/fusio.zip && rm /tmp/fusio.zip \
    && rm -f public/install.php \
    # the official image's configuration.php: FUSIO_* variable names, log to stderr
    && sed -i -e "s/env('APP_/env('FUSIO_/" \
              -e "s|'psx_path_log' *=> __DIR__ . '/log',|'psx_path_log'             => 'php://error_log',|" configuration.php \
    && grep -q "env('FUSIO_CONNECTION')" configuration.php && grep -q "php://error_log" configuration.php \
    # every setting comes from the container environment
    && : > .env
RUN cd /src/public/apps \
    && mkdir fusio developer account \
    && curl -fsSL -o /tmp/a.zip "https://github.com/apioo/fusio-apps-backend/releases/download/v${FUSIO_APP_BACKEND}/fusio.zip" && unzip -q /tmp/a.zip -d fusio \
    && curl -fsSL -o /tmp/a.zip "https://github.com/apioo/fusio-apps-developer/releases/download/v${FUSIO_APP_DEVELOPER}/developer.zip" && unzip -q /tmp/a.zip -d developer \
    && curl -fsSL -o /tmp/a.zip "https://github.com/apioo/fusio-apps-account/releases/download/v${FUSIO_APP_ACCOUNT}/account.zip" && unzip -q /tmp/a.zip -d account \
    && curl -fsSL -o /tmp/a.zip "https://github.com/apioo/fusio-apps-redoc/archive/refs/tags/v${FUSIO_APP_REDOC}.zip" && unzip -q /tmp/a.zip \
    && mv "fusio-apps-redoc-${FUSIO_APP_REDOC}" redoc && rm /tmp/a.zip

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

COPY --from=src /src /app
COPY ephpm.toml /etc/ephpm/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
# `php` on PATH for anything that shells out to PHP (PHP_BINARY is `ephpm`
# under `ephpm php`, ephpm#558).
RUN printf '#!/bin/sh\nexec ephpm php "$@"\n' > /usr/local/bin/php && chmod +x /usr/local/bin/php \
    && chmod +x /usr/local/bin/entrypoint.sh /app/bin/fusio
ENV PHP_BINARY=/usr/local/bin/php \
    FUSIO_ENV=prod \
    FUSIO_DEBUG=false \
    FUSIO_MAILER=native://default \
    FUSIO_MESSENGER=doctrine://default \
    FUSIO_URL= \
    FUSIO_APPS_URL= \
    FUSIO_MAIL_SENDER= \
    FUSIO_TRUSTED_IP_HEADER= \
    FUSIO_TENANT_ID=
WORKDIR /app

EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
