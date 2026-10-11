# Grocy on ePHPm.
#
# One container replaces the linuxserver/grocy image (nginx + php-fpm + s6):
# ePHPm serves public/ and runs PHP; Grocy keeps its own SQLite database in
# the data volume.
#
# Build args:
#   EPHPM_TAG      ephpm/ephpm image tag (default v0.11.3-php8.5 — Grocy 4.7
#                  requires PHP 8.5.*)
#   GROCY_VERSION  Grocy release (default 4.7.1)

ARG EPHPM_TAG=v0.11.3-php8.5
ARG GROCY_VERSION=4.7.1

# ── Stage 1: the release zip (PHP dependencies and front-end packages included) ──
FROM docker.io/library/alpine:3.20 AS src
ARG GROCY_VERSION
RUN apk add --no-cache curl unzip
RUN curl -fsSL -o /grocy.zip "https://github.com/grocy/grocy/releases/download/v${GROCY_VERSION}/grocy_${GROCY_VERSION}.zip" \
    && mkdir /src && unzip -q /grocy.zip -d /src

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

COPY --from=src /src /var/www/html
COPY ephpm.toml /etc/ephpm/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh \
    && mkdir -p /var/lib/ephpm \
    # pristine copy of data/ (plugins dir), used to seed an empty volume
    && mkdir -p /usr/local/share/grocy \
    && cp -a /var/www/html/data /usr/local/share/grocy/data

WORKDIR /var/www/html
VOLUME ["/var/www/html/data"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
