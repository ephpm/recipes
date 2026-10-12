# Open Web Analytics on ePHPm.
#
# One container replaces the Apache/nginx + php-fpm setup OWA is normally
# deployed on (there is no official image): ePHPm serves the admin UI
# (index.php), the tracking endpoint (log.php), the REST API (api/) and the
# static assets, and runs PHP; OWA's cli.php (install, scheduled jobs,
# updates) runs on the embedded PHP.
#
# Build args:
#   EPHPM_TAG     ephpm/ephpm image tag (default v0.11.3-php8.5)
#   OWA_VERSION   OWA release (default 1.14.0)

ARG EPHPM_TAG=v0.11.3-php8.5
ARG OWA_VERSION=1.14.0

# ── Stage 1: the packaged release (vendor/ included) ───────────────────────
FROM docker.io/library/alpine:3.20 AS src
ARG OWA_VERSION
RUN apk add --no-cache curl tar
RUN mkdir -p /src \
    && curl -fsSL "https://github.com/Open-Web-Analytics/Open-Web-Analytics/releases/download/${OWA_VERSION}/owa_${OWA_VERSION}_packaged.tar" \
       | tar x -C /src

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

COPY --from=src /src /var/www/owa
COPY ephpm.toml /etc/ephpm/ephpm.toml
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY owa-cli /usr/local/bin/owa-cli
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/owa-cli \
    # owa-config.php (DB credentials, keys) is generated into the owa-data
    # volume on first start; OWA reads it from the application root.
    && ln -s /var/www/owa/owa-data/owa-config.php /var/www/owa/owa-config.php \
    # pristine copy, used by entrypoint.sh to seed an empty owa-data volume
    && cp -a /var/www/owa/owa-data /usr/local/share/owa-data

WORKDIR /var/www/owa
VOLUME ["/var/www/owa/owa-data"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
