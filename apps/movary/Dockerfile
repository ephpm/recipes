# Movary on ePHPm.
#
# One container replaces the official leepeuker/movary image (nginx + php-fpm
# + the job worker under supervisord): ePHPm serves public/ and runs PHP;
# the FastRoute front-controller rewrite comes from ephpm.toml. The job
# worker is a second service in compose.yml running the same image.
#
# Build args:
#   EPHPM_TAG       ephpm/ephpm image tag (default v0.11.3-php8.5 — Movary needs PHP 8.5)
#   MOVARY_VERSION  Movary release tag to build (default 0.77.0)

ARG EPHPM_TAG=v0.11.3-php8.5
ARG MOVARY_VERSION=0.77.0

# ── Stage 1: source + PHP dependencies ───────────────────────────────────────
# No dist archive is published; the tag's tree already contains the frontend
# (plain JS/CSS under public/), so only Composer runs here. Platform checks
# are off because the composer image's PHP is older than 8.5 — the code only
# ever runs on the embedded PHP below.
FROM docker.io/library/composer:2 AS deps
ARG MOVARY_VERSION
RUN curl -fsSL "https://github.com/leepeuker/movary/archive/refs/tags/${MOVARY_VERSION}.tar.gz" \
      | tar xz -C /tmp \
    && rm -rf /src && mv "/tmp/movary-${MOVARY_VERSION}" /src
WORKDIR /src
RUN composer install --no-dev --no-scripts --no-interaction --no-progress \
        --prefer-dist --optimize-autoloader --ignore-platform-reqs \
    && rm -rf tests build docs .github docker-compose*.yml mkdocs.yml Makefile \
    && printf '%s' "${MOVARY_VERSION}" > .version

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}
ARG MOVARY_VERSION
ENV APPLICATION_VERSION=${MOVARY_VERSION}

# Same location as the official image.
COPY --from=deps /src /app
COPY ephpm.toml /etc/ephpm/
COPY movary /usr/local/bin/movary
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
WORKDIR /app
RUN chmod +x /usr/local/bin/movary /usr/local/bin/entrypoint.sh \
    && mkdir -p /var/lib/ephpm storage/app storage/logs \
    # pristine copy, used by entrypoint.sh to seed an empty storage volume
    && cp -a storage /usr/local/share/movary-storage

VOLUME ["/app/storage"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
