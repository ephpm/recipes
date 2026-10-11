# Matomo on ePHPm.
#
# One container replaces Apache + mod_php (the matomo:apache image) or
# nginx + php-fpm: ePHPm serves the files and runs index.php / matomo.php;
# the console (archiving, GeoIP updates, …) runs on the embedded PHP CLI.
#
# Build args:
#   EPHPM_TAG       ephpm/ephpm image tag (default v0.11.3-php8.5)
#   MATOMO_VERSION  Matomo release to bake in (default 5.14.1)

ARG EPHPM_TAG=v0.11.3-php8.5
ARG MATOMO_VERSION=5.14.1

# ── Stage 1: the release zip from builds.matomo.org (vendor/ included) ───────
FROM docker.io/library/alpine:3.20 AS src
ARG MATOMO_VERSION
RUN apk add --no-cache curl unzip
RUN curl -fsSL -o /matomo.zip "https://builds.matomo.org/matomo-${MATOMO_VERSION}.zip" \
    && unzip -q /matomo.zip -d /unpacked && mv /unpacked/matomo /src && rm -rf /matomo.zip /unpacked \
    && rm -rf /src/tests

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

COPY --from=src /src /var/www/html
COPY php /usr/local/bin/php
COPY ephpm.toml /etc/ephpm/ephpm.toml
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/php /usr/local/bin/entrypoint.sh /var/www/html/console \
    && mkdir -p /var/www/html/tmp /var/www/html/misc/user \
    # pristine copies, used by entrypoint.sh to seed empty volumes
    && mkdir -p /usr/local/share/matomo \
    && cp -a /var/www/html/config /var/www/html/plugins /var/www/html/misc/user /usr/local/share/matomo/

WORKDIR /var/www/html
VOLUME ["/var/www/html/config", "/var/www/html/plugins", "/var/www/html/misc/user", "/var/www/html/tmp"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
