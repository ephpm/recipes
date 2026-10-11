# Part-DB on ePHPm.
#
# One container replaces the official jbtronics/part-db1 image (Apache +
# php-fpm): ePHPm serves public/ and runs PHP; the Symfony front-controller
# rewrite comes from ephpm.toml.
#
# Build args:
#   EPHPM_TAG       ephpm/ephpm image tag (default v0.11.3-php8.5)
#   PARTDB_VERSION  Part-DB release to bake in (default 2.20.0)

ARG EPHPM_TAG=v0.11.3-php8.5
ARG PARTDB_VERSION=2.20.0

# ── Stage 1: fetch the release zip (vendor/ and public/build included) ───────
FROM docker.io/library/alpine:3.20 AS src
ARG PARTDB_VERSION
RUN apk add --no-cache curl unzip
RUN curl -fsSL -o /partdb.zip \
        "https://github.com/Part-DB/Part-DB-server/releases/download/v${PARTDB_VERSION}/partdb_with_assets.zip" \
    && mkdir /src && unzip -q /partdb.zip -d /src && rm /partdb.zip \
    && rm -rf /src/tests /src/.devcontainer /src/.docker /src/.github /src/docs \
              /src/Dockerfile /src/var/cache/* /src/var/log/* \
    && mkdir -p /src/var/cache /src/var/log /src/var/db /src/uploads /src/public/media

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

# Same location as the official image, so documentation paths carry over.
COPY --from=src /src /var/www/html
COPY ephpm.toml /etc/ephpm/
COPY partdb /usr/local/bin/partdb
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
WORKDIR /var/www/html
RUN chmod +x /usr/local/bin/partdb /usr/local/bin/entrypoint.sh \
    && mkdir -p /var/lib/ephpm \
    # pristine copies, used by entrypoint.sh to seed empty volumes
    && mkdir -p /usr/local/share/partdb \
    && cp -a uploads /usr/local/share/partdb/uploads \
    && cp -a public/media /usr/local/share/partdb/media

VOLUME ["/var/www/html/uploads", "/var/www/html/public/media", "/var/www/html/var/db"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
