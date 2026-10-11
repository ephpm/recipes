# Kimai on ePHPm.
#
# One container replaces the official kimai/kimai2 image (php-fpm + a separate
# nginx, or Apache): ePHPm serves public/ and runs PHP; the Symfony
# front-controller rewrite comes from ephpm.toml.
#
# Build args:
#   EPHPM_TAG      ephpm/ephpm image tag (default v0.11.3-php8.5)
#   KIMAI_VERSION  Kimai release tag to build (default 2.69.0)

ARG EPHPM_TAG=v0.11.3-php8.5
ARG KIMAI_VERSION=2.69.0

# ── Stage 1: fetch the release source and install PHP dependencies ───────────
# Kimai publishes no dist archive; the tag's tree already contains the
# compiled frontend (public/build), so only Composer runs here. Scripts are
# skipped: cache:clear / assets:install run on the embedded PHP below.
FROM docker.io/library/composer:2 AS build
ARG KIMAI_VERSION
RUN curl -fsSL "https://github.com/kimai/kimai/archive/refs/tags/${KIMAI_VERSION}.tar.gz" \
      | tar xz -C /tmp \
    && rm -rf /src && mv "/tmp/kimai-${KIMAI_VERSION}" /src
WORKDIR /src
RUN composer install --no-dev --no-scripts --no-interaction --no-progress \
        --prefer-dist --optimize-autoloader --ignore-platform-reqs \
    && rm -rf tests assets .docker .github var/cache/* var/log/* \
    && echo "${KIMAI_VERSION}" > version.txt

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

# Same location as the official image, so documentation paths carry over.
COPY --from=build /src /opt/kimai
COPY ephpm.toml /etc/ephpm/
COPY kimai /usr/local/bin/kimai
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
WORKDIR /opt/kimai
RUN chmod +x /usr/local/bin/kimai /usr/local/bin/entrypoint.sh \
    && mkdir -p /var/lib/ephpm var/data var/log var/plugins var/sessions \
    # The Composer "auto-scripts" the build stage skipped, on the embedded
    # PHP (a dummy DATABASE_URL: the cache warm-up opens no connection).
    && APP_ENV=prod APP_SECRET=build DATABASE_URL="mysql://x:x@127.0.0.1/x?serverVersion=11.4.0-MariaDB" \
       ephpm php bin/console assets:install --no-interaction \
    && rm -rf var/cache/* \
    # pristine copy, used by entrypoint.sh to seed an empty var/ volume
    && cp -a var /usr/local/share/kimai-var

VOLUME ["/opt/kimai/var"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
