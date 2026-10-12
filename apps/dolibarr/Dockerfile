# Dolibarr ERP/CRM on ePHPm.
#
# One container replaces the official dolibarr/dolibarr image (php-apache,
# with the mysql client its entrypoint uses to load the schema): ePHPm
# serves htdocs/ and runs PHP; the schema is loaded by a small PHP script
# over mysqli instead.
#
# Build args:
#   EPHPM_TAG        ephpm/ephpm image tag (default v0.11.3-php8.4 —
#                    Dolibarr 24 warns about PHP newer than 8.5.0)
#   DOLI_VERSION     Dolibarr release tag (default 24.0.2)

ARG EPHPM_TAG=v0.11.3-php8.4
ARG DOLI_VERSION=24.0.2

# ── Stage 1: fetch the release source (what the official Dockerfile does) ───
FROM docker.io/library/alpine:3.20 AS src
ARG DOLI_VERSION
RUN apk add --no-cache curl tar
RUN mkdir /src \
    && curl -fsSL "https://github.com/Dolibarr/dolibarr/archive/${DOLI_VERSION}.tar.gz" \
       | tar xz --strip-components=1 -C /src \
    && mkdir /out && mv /src/htdocs /out/htdocs && mv /src/scripts /out/scripts \
    && rm -rf /src

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}
ARG DOLI_VERSION

COPY --from=src /out /var/www/dolibarr
COPY ephpm.toml /etc/ephpm/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY init-db.php init-modules.php /var/www/dolibarr/ephpm/
RUN chmod +x /usr/local/bin/entrypoint.sh \
    && mkdir -p /var/lib/ephpm /var/www/documents /var/www/dolibarr/htdocs/custom /var/www/dolibarr/htdocs/conf

ENV DOLI_VERSION=${DOLI_VERSION}
WORKDIR /var/www/dolibarr/htdocs
VOLUME ["/var/www/documents", "/var/www/dolibarr/htdocs/custom"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
