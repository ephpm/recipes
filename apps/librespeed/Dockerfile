# LibreSpeed on ePHPm.
#
# One container replaces the official image's Apache + mod_php: ePHPm serves
# the HTML/JS front end and runs the three backend endpoints (garbage.php,
# empty.php, getIP.php) plus the optional telemetry/stats pages.
#
# The layout matches ghcr.io/librespeed/speedtest: the sources sit in
# /speedtest and entrypoint.sh assembles /var/www/html from them at every
# start, according to MODE / TELEMETRY / DB_TYPE (same variables).
#
# Build args:
#   EPHPM_TAG           ephpm/ephpm image tag (default v0.11.3-php8.5)
#   LIBRESPEED_VERSION  LibreSpeed release tag (default v6.3.0)

ARG EPHPM_TAG=v0.11.3-php8.5
ARG LIBRESPEED_VERSION=v6.3.0

# ── Stage 1: the release source, cut down to what the official image copies ──
FROM docker.io/library/alpine:3.20 AS src
ARG LIBRESPEED_VERSION
RUN apk add --no-cache curl tar
RUN mkdir -p /tmp/ls /speedtest/results \
    && curl -fsSL "https://github.com/librespeed/speedtest/archive/refs/tags/${LIBRESPEED_VERSION}.tar.gz" \
       | tar xz --strip-components=1 -C /tmp/ls \
    && cd /tmp/ls \
    && cp -a backend frontend images /speedtest/ \
    && cp results/*.php results/*.ttf /speedtest/results/ \
    && cp *.js index.html index-classic.html index-modern.html config.json settings.json \
          server-list.json stability.html favicon.ico manifest.webmanifest /speedtest/

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

COPY --from=src /speedtest /speedtest
# The base image ships ePHPm's own test fixtures in /var/www/html (phpinfo()
# among them, see issues/joomla.md); entrypoint.sh rebuilds the web root anyway.
RUN rm -rf /var/www/html
COPY ephpm.toml /etc/ephpm/ephpm.toml
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh \
    && mkdir -p /var/www/html /database /var/lib/ephpm

# Same defaults as the official image.
ENV TITLE=LibreSpeed \
    TAGLINE="No Flash, No Java, No Websockets, No Bullsh*t" \
    MODE=standalone \
    PASSWORD=password \
    TELEMETRY=false \
    ENABLE_ID_OBFUSCATION=false \
    REDACT_IP_ADDRESSES=false \
    USE_NEW_DESIGN=false

WORKDIR /var/www/html
VOLUME ["/database"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
