# Shlink on ePHPm.
#
# The official shlinkio/shlink image runs RoadRunner (a persistent PHP worker
# behind its own HTTP server). This recipe runs the same release dist in
# ePHPm's per-request mode through public/index.php — the layout Shlink's
# "classic web server" (nginx/apache + php-fpm) documentation describes —
# with ePHPm as the one process. Shlink's own CLI (`bin/cli`) runs on the
# embedded PHP.
#
# Build args:
#   EPHPM_TAG       ephpm/ephpm image tag (default v0.11.3-php8.5)
#   SHLINK_VERSION  Shlink release to bake in (default 5.1.7)
#   SHLINK_PHP      PHP minor of the dist zip to fetch (default 8.5; must match EPHPM_TAG)

ARG EPHPM_TAG=v0.11.3-php8.5
ARG SHLINK_VERSION=5.1.7
ARG SHLINK_PHP=8.5

# ── Stage 1: fetch the release dist (vendor/ included, no build step) ────────
FROM docker.io/library/alpine:3.20 AS src
ARG SHLINK_VERSION
ARG SHLINK_PHP
RUN apk add --no-cache curl unzip
RUN curl -fsSL -o /shlink.zip \
        "https://github.com/shlinkio/shlink/releases/download/v${SHLINK_VERSION}/shlink${SHLINK_VERSION}_php${SHLINK_PHP}_dist.zip" \
    && unzip -q /shlink.zip -d /unzip \
    && mv "/unzip/shlink${SHLINK_VERSION}_php${SHLINK_PHP}_dist" /src \
    && rm -rf /unzip /shlink.zip \
    && mkdir -p /src/data/cache /src/data/locks /src/data/log /src/data/proxies /src/data/temp-geolite

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

# Same location as the official image, so documentation paths carry over.
COPY --from=src /src /etc/shlink
COPY ephpm.toml /etc/ephpm/
COPY shlink /usr/local/bin/shlink
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/shlink /usr/local/bin/entrypoint.sh \
    && mkdir -p /var/lib/ephpm \
    # pristine copy, used by entrypoint.sh to seed an empty data volume
    && cp -a /etc/shlink/data /usr/local/share/shlink-data

WORKDIR /etc/shlink
VOLUME ["/etc/shlink/data"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
