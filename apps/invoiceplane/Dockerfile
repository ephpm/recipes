# InvoicePlane on ePHPm.
#
# One container replaces the official two-container nginx + php-fpm setup
# (and the single php:8.2-apache image): ePHPm serves the static assets, runs
# PHP, and answers the front-controller rewrite from ephpm.toml.
#
# Build args:
#   EPHPM_TAG   ephpm/ephpm image tag (default v0.11.3-php8.5)
#   IP_VERSION  InvoicePlane release to bake in (default 1.7.2)

ARG EPHPM_TAG=v0.11.3-php8.5
ARG IP_VERSION=1.7.2

# ── Stage 1: fetch the release zip (ships vendor/ and the built assets) ──────
FROM docker.io/library/alpine:3.20 AS src
ARG IP_VERSION
RUN apk add --no-cache curl unzip
RUN curl -fsSL -o /ip.zip \
        "https://github.com/InvoicePlane/InvoicePlane/releases/download/v${IP_VERSION}/v${IP_VERSION}.zip" \
    && unzip -q /ip.zip -d /unzip \
    && mv /unzip/ip /src \
    && rm -rf /unzip /ip.zip \
    # not web content: the upstream docker/dev tooling and the apache rules
    && rm -rf /src/resources /src/docker-compose.yml /src/compose.yml \
              /src/htaccess /src/Gruntfile.js /src/package.json /src/yarn.lock \
              /src/*.neon /src/pint.json /src/rector.php /src/phpcs.xml \
    && mkdir -p /src/application/logs /src/storage/temp \
                /src/uploads/temp/mpdf

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

# The base image ships ePHPm's E2E fixtures in /var/www/html (phpinfo()
# among them, issues/joomla.md): start from an empty web root.
RUN rm -rf /var/www/html
COPY --from=src /src /var/www/html
COPY ephpm.toml /etc/ephpm/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh \
    && mkdir -p /var/lib/ephpm \
    # pristine copies, used by entrypoint.sh to seed empty volumes
    && mkdir -p /usr/local/share/invoiceplane \
    && cp -a /var/www/html/uploads /usr/local/share/invoiceplane/uploads \
    && cp -a /var/www/html/storage /usr/local/share/invoiceplane/storage

VOLUME ["/var/www/html/uploads", "/var/www/html/storage"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
