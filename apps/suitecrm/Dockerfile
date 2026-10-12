# SuiteCRM 7 on ePHPm.
#
# One container replaces Apache + mod_php (the usual SuiteCRM 7 deployment,
# e.g. the bitnami image) plus the system crontab: ePHPm serves the app and
# runs PHP; the compose file's `cron` service runs cron.php every minute on
# the same image.
#
# Build args:
#   EPHPM_TAG          ephpm/ephpm image tag (default v0.11.3-php8.4)
#   SUITECRM_VERSION   SuiteCRM 7 release (default 7.15.2)
#
# The release zip ships vendor/, so there is no Composer stage.

ARG EPHPM_TAG=v0.11.3-php8.4
ARG SUITECRM_VERSION=7.15.2

# ── Stage 1: the release zip ─────────────────────────────────────────────────
FROM docker.io/library/alpine:3.20 AS src
ARG SUITECRM_VERSION
RUN apk add --no-cache curl unzip
RUN curl -fsSL -o /tmp/suitecrm.zip \
        "https://github.com/salesagility/SuiteCRM/releases/download/v${SUITECRM_VERSION}/SuiteCRM-${SUITECRM_VERSION}.zip" \
    && unzip -q /tmp/suitecrm.zip -d /tmp/x \
    && mv /tmp/x/SuiteCRM-${SUITECRM_VERSION} /src \
    && rm -rf /tmp/x /tmp/suitecrm.zip /src/tests

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

# SuiteCRM 7 writes into its own tree (config.php, custom/, cache/, upload/,
# modules/ for Studio and Module Builder), so the tree lives in a volume and
# is seeded from this pristine copy on first start, as the official
# WordPress image does.
COPY --from=src /src /usr/src/suitecrm
# The base image ships ePHPm's own test fixtures in /var/www/html (phpinfo()
# among them, see issues/joomla.md); start from an empty directory.
RUN rm -rf /var/www/html && mkdir -p /var/www/html
COPY php /usr/local/bin/php
COPY ephpm.toml /etc/ephpm/ephpm.toml
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY si-install.php /usr/local/share/suitecrm-si-install.php
RUN chmod +x /usr/local/bin/php /usr/local/bin/entrypoint.sh

WORKDIR /var/www/html
VOLUME ["/var/www/html"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
