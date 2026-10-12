# selfoss on ePHPm.
#
# One container replaces Apache (+ .htaccess) or nginx + php-fpm, plus the
# cron job that refreshes the feeds: ePHPm serves selfoss and runs PHP; the
# compose file's `updater` service runs cliupdate.php on the same image.
#
# Build args:
#   EPHPM_TAG         ephpm/ephpm image tag (default v0.11.3-php8.5)
#   SELFOSS_VERSION   release (default 2.19, the latest tagged release)
#
# The release zip ships vendor/ and the built front end.

ARG EPHPM_TAG=v0.11.3-php8.5
ARG SELFOSS_VERSION=2.19

# ── Stage 1: the release zip ─────────────────────────────────────────────────
FROM docker.io/library/alpine:3.20 AS src
ARG SELFOSS_VERSION
RUN apk add --no-cache curl unzip
RUN curl -fsSL -o /tmp/selfoss.zip \
        "https://github.com/fossar/selfoss/releases/download/${SELFOSS_VERSION}/selfoss-${SELFOSS_VERSION}.zip" \
    && unzip -q /tmp/selfoss.zip -d /tmp/x && mv /tmp/x/selfoss /src \
    && rm -rf /tmp/x /tmp/selfoss.zip

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

COPY --from=src /src /app
COPY php /usr/local/bin/php
COPY ephpm.toml /etc/ephpm/ephpm.toml
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/php /usr/local/bin/entrypoint.sh \
    # pristine copy, used by entrypoint.sh to seed an empty data volume
    && cp -a /app/data /usr/local/share/selfoss-data

WORKDIR /app
VOLUME ["/app/data"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
