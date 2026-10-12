# InvoiceShelf on ePHPm.
#
# One container replaces the official image's nginx + php-fpm (+ cron):
# ePHPm serves public/ and runs PHP; the compose file's `scheduler` service
# runs Laravel's scheduler on the same image.
#
# Build args:
#   EPHPM_TAG              ephpm/ephpm image tag (default v0.11.3-php8.5; InvoiceShelf 2 needs PHP >= 8.4)
#   INVOICESHELF_VERSION   release tag (default 2.4.6)
#
# The release zip (InvoiceShelf.zip) ships vendor/ and the built front end.

ARG EPHPM_TAG=v0.11.3-php8.5
ARG INVOICESHELF_VERSION=2.4.6

# ── Stage 1: the release zip ─────────────────────────────────────────────────
FROM docker.io/library/alpine:3.20 AS src
ARG INVOICESHELF_VERSION
RUN apk add --no-cache curl unzip
RUN curl -fsSL -o /tmp/is.zip \
        "https://github.com/InvoiceShelf/InvoiceShelf/releases/download/${INVOICESHELF_VERSION}/InvoiceShelf.zip" \
    && unzip -q /tmp/is.zip -d /tmp/x && mv /tmp/x/InvoiceShelf /src \
    && rm -rf /tmp/x /tmp/is.zip

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

COPY --from=src /src /app
COPY php /usr/local/bin/php
COPY ephpm.toml /etc/ephpm/ephpm.toml
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY setup.php /usr/local/share/invoiceshelf/setup.php
# PHP_BINARY under `ephpm php` is `ephpm` itself (ephpm#558); Laravel's
# scheduler re-spawns PHP through Symfony's PhpExecutableFinder, which
# honours this variable (issues/pterodactyl.md).
ENV PHP_BINARY=/usr/local/bin/php
RUN chmod +x /usr/local/bin/php /usr/local/bin/entrypoint.sh \
    # pristine copy, used by entrypoint.sh to seed an empty storage volume
    && cp -a /app/storage /usr/local/share/invoiceshelf/storage

WORKDIR /app
VOLUME ["/app/storage"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
