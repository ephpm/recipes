# EspoCRM on ePHPm.
#
# One container replaces the official espocrm/espocrm image (apache or
# php-fpm + a separate daemon container): ePHPm serves public/ and runs
# PHP; the scheduler runs in a second service of compose.yml. The rewrites
# EspoCRM needs (root .htaccess into public/, public/api/v1/.htaccess,
# public/portal/.htaccess) are a small PHP front controller (front.php).
#
# Build args:
#   EPHPM_TAG        ephpm/ephpm image tag (default v0.11.3-php8.4 — the official image ships PHP 8.4)
#   ESPOCRM_VERSION  EspoCRM release to bake in (default 10.0.9)

ARG EPHPM_TAG=v0.11.3-php8.4
ARG ESPOCRM_VERSION=10.0.9

# ── Stage 1: fetch the release zip (vendor/ and the built client included) ───
FROM docker.io/library/alpine:3.20 AS src
ARG ESPOCRM_VERSION
RUN apk add --no-cache curl unzip
RUN curl -fsSL -o /espocrm.zip \
        "https://github.com/espocrm/espocrm/releases/download/${ESPOCRM_VERSION}/EspoCRM-${ESPOCRM_VERSION}.zip" \
    && unzip -q /espocrm.zip -d /unzip \
    && mv "/unzip/EspoCRM-${ESPOCRM_VERSION}" /src && rm -rf /unzip /espocrm.zip \
    # the web installer is replaced by the entrypoint, as in the official image
    && rm -rf /src/install /src/public/install

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

# Same location as the official image.
# The base image ships ePHPm's E2E fixtures in /var/www/html (phpinfo()
# among them, issues/joomla.md): start from an empty web root.
RUN rm -rf /var/www/html
COPY --from=src /src /var/www/html
COPY front.php /var/www/html/ephpm-front.php
COPY ephpm.toml /etc/ephpm/
COPY espocrm /usr/local/bin/espocrm
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
WORKDIR /var/www/html
RUN chmod +x /usr/local/bin/espocrm /usr/local/bin/entrypoint.sh bin/command \
    && mkdir -p /var/lib/ephpm data custom client/custom \
    # pristine copies, used by entrypoint.sh to seed empty volumes
    && mkdir -p /usr/local/share/espocrm \
    && cp -a data /usr/local/share/espocrm/data \
    && cp -a custom /usr/local/share/espocrm/custom \
    && cp -a client/custom /usr/local/share/espocrm/client-custom

VOLUME ["/var/www/html/data", "/var/www/html/custom", "/var/www/html/client/custom"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
