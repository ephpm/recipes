# FreeScout on ePHPm.
#
# One container replaces Apache/nginx + php-fpm + the crontab entry for
# `artisan schedule:run`: ePHPm serves public/ and runs PHP; the scheduler
# and the queue worker are sidecars from the same image.
#
# Build args:
#   EPHPM_TAG           ephpm/ephpm image tag (default v0.11.3-php8.5)
#   FREESCOUT_VERSION   FreeScout release tag (default 1.8.247)
#
# FreeScout commits vendor/ (with its own patched framework under
# overrides/), so the release tag is used as is — no Composer stage.

ARG EPHPM_TAG=v0.11.3-php8.5
ARG FREESCOUT_VERSION=1.8.247

# ── Stage 1: the release tag ─────────────────────────────────────────────────
FROM docker.io/library/alpine:3.20 AS src
ARG FREESCOUT_VERSION
RUN apk add --no-cache curl tar
RUN mkdir -p /src \
    && curl -fsSL "https://codeload.github.com/freescout-help-desk/freescout/tar.gz/refs/tags/${FREESCOUT_VERSION}" \
       | tar xz --strip-components=1 -C /src \
    && rm -rf /src/tests /src/.github /src/.travis.yml /src/.env.travis

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

# `ps`: FreeScout's scheduler inspects running queue workers with it.
RUN apt-get update \
    && apt-get install -y --no-install-recommends procps \
    && rm -rf /var/lib/apt/lists/*

COPY --from=src /src /app
# Laravel's scheduler starts every scheduled command as
# `<PHP_BINARY> artisan ...`; PHP_BINARY is `ephpm` here (ephpm#558), which
# would run `ephpm artisan ...` and fail silently. Let FreeScout's patched
# Console\Application take the PHP binary from LARAVEL_PHP_BINARY (set below
# to the `php` shim) and fall back to its own lookup otherwise.
RUN sed -i 's|return ProcessUtils::escapeArgument((new PhpExecutableFinder)->find(false));|return ProcessUtils::escapeArgument(getenv('"'"'LARAVEL_PHP_BINARY'"'"') ?: (new PhpExecutableFinder)->find(false));|' \
        /app/overrides/laravel/framework/src/Illuminate/Console/Application.php \
    && grep -q LARAVEL_PHP_BINARY /app/overrides/laravel/framework/src/Illuminate/Console/Application.php
ENV LARAVEL_PHP_BINARY=/usr/local/bin/php
COPY ephpm.toml /etc/ephpm/ephpm.toml
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
# `php` on PATH: FreeScout's docs and module installer call `php artisan`;
# PHP_BINARY is `ephpm` here (ephpm#558), so give them `ephpm php`.
RUN printf '#!/bin/sh\nexec ephpm php "$@"\n' > /usr/local/bin/php \
    && chmod +x /usr/local/bin/php /usr/local/bin/entrypoint.sh \
    # pristine storage/ to seed the volume; .env lives in it
    && cp -a /app/storage /usr/local/share/freescout-storage \
    && ln -sfn /app/storage/.env /app/.env \
    && mkdir -p /var/lib/ephpm \
    # the base image's E2E fixtures (issues/joomla.md) are not needed here
    && rm -rf /var/www/html

WORKDIR /app
VOLUME ["/app/storage"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
