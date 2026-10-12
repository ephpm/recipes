# Lychee on ePHPm.
#
# One container replaces the official image's FrankenPHP (Octane worker)
# server: ePHPm serves public/ and runs Lychee in per-request mode (Lychee's
# Octane integration is FrankenPHP-specific; there is no ePHPm Octane
# adapter wired for it here).
#
# Build args:
#   EPHPM_TAG        ephpm/ephpm image tag (default v0.11.3-php8.5; Lychee 7 needs PHP >= 8.4)
#   LYCHEE_VERSION   release tag (default v7.10.0)
#
# The release zip (Lychee.zip) ships vendor/ and the built front end.

ARG EPHPM_TAG=v0.11.3-php8.5
ARG LYCHEE_VERSION=v7.10.0

# ── Stage 1: the release zip ─────────────────────────────────────────────────
FROM docker.io/library/alpine:3.20 AS src
ARG LYCHEE_VERSION
RUN apk add --no-cache curl unzip
RUN curl -fsSL -o /tmp/lychee.zip \
        "https://github.com/LycheeOrg/Lychee/releases/download/${LYCHEE_VERSION}/Lychee.zip" \
    && unzip -q /tmp/lychee.zip -d /tmp/x && mv /tmp/x/Lychee /src \
    && rm -rf /tmp/x /tmp/lychee.zip /src/composer-cache

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

COPY --from=src /src /app
COPY php /usr/local/bin/php
COPY ephpm.toml /etc/ephpm/ephpm.toml
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
# PHP_BINARY under `ephpm php` is `ephpm` itself (ephpm#558); Laravel's
# scheduler and queue re-spawn PHP through Symfony's PhpExecutableFinder,
# which honours this variable (issues/pterodactyl.md).
ENV PHP_BINARY=/usr/local/bin/php
RUN chmod +x /usr/local/bin/php /usr/local/bin/entrypoint.sh \
    # pristine copies, used by entrypoint.sh to seed empty volumes
    && mkdir -p /usr/local/share/lychee \
    && cp -a /app/storage /app/public/uploads /usr/local/share/lychee/

WORKDIR /app
VOLUME ["/app/storage", "/app/public/uploads"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
