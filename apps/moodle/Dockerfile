# Moodle on ePHPm.
#
# One container replaces Apache/nginx + php-fpm: ePHPm serves public/ (the
# web root since Moodle 5.1) and routes everything else to the Moodle router
# (r.php); the admin CLI (install, upgrade, cron) runs on the embedded PHP,
# and cron runs as a sidecar from the same image.
#
# Build args:
#   EPHPM_TAG       ephpm/ephpm image tag (default v0.11.3-php8.5)
#   MOODLE_VERSION  Moodle git tag (default v5.3.0)

ARG EPHPM_TAG=v0.11.3-php8.5
ARG MOODLE_VERSION=v5.3.0

# ── Stage 1: the release tag + Composer dependencies ─────────────────────────
FROM docker.io/library/composer:2 AS src
ARG MOODLE_VERSION
RUN mkdir -p /src \
    && curl -fsSL "https://github.com/moodle/moodle/archive/refs/tags/${MOODLE_VERSION}.tar.gz" \
       | tar xz --strip-components=1 -C /src \
    && cd /src \
    && composer install --no-dev --no-interaction --no-progress --prefer-dist \
        --ignore-platform-reqs --optimize-autoloader \
    && rm -rf .github .grunt .jest .esbuild node_modules /root/.composer /tmp/*

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

COPY --from=src /src /var/www/moodle
COPY config.php /var/www/moodle/config.php
COPY ephpm.toml /etc/ephpm/ephpm.toml
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
# `php` on PATH: Moodle's admin CLI and docs use `php admin/cli/...`. The CLI does
# not read [php] ini_overrides, and Moodle's environment check (run by the
# installer and upgrader) insists on max_input_vars >= 5000, so the shim sets it.
RUN printf '#!/bin/sh\nexec ephpm php -d max_input_vars=5000 "$@"\n' > /usr/local/bin/php \
    && chmod +x /usr/local/bin/php /usr/local/bin/entrypoint.sh \
    && mkdir -p /var/moodledata /var/lib/ephpm \
    # the base image's E2E fixtures (issues/joomla.md) are not needed here
    && rm -rf /var/www/html

WORKDIR /var/www/moodle
VOLUME ["/var/moodledata"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
