# OpenCart on ePHPm.
#
# OpenCart has no official production image; this replaces the usual
# nginx + php-fpm (or apache) host with ePHPm serving the shop and running
# PHP.
#
# Build args:
#   EPHPM_TAG          ephpm/ephpm image tag (default v0.11.3-php8.5)
#   OPENCART_VERSION   OpenCart release (default 4.1.0.4)

ARG EPHPM_TAG=v0.11.3-php8.5
ARG OPENCART_VERSION=4.1.0.4

# ── Stage 1: fetch the release zip (upload/ is the web root) ─────────────────
FROM docker.io/library/alpine:3.20 AS src
ARG OPENCART_VERSION
RUN apk add --no-cache curl unzip
RUN curl -fsSL -o /oc.zip \
        "https://github.com/opencart/opencart/releases/download/${OPENCART_VERSION}/opencart-${OPENCART_VERSION}.zip" \
    && mkdir /x && unzip -q /oc.zip -d /x \
    && mv "$(find /x -maxdepth 2 -type d -name upload | head -n1)" /src \
    && rm -rf /oc.zip /x

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

# Pristine copy; entrypoint.sh copies it into the /var/www/opencart volume
# on the first start (OpenCart writes config.php, admin/config.php, images,
# extensions and its storage directory inside its own tree).
COPY --from=src /src /usr/src/opencart
COPY ephpm.toml /etc/ephpm/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh && mkdir -p /var/lib/ephpm /var/www/opencart

# (not /var/www/html: the ephpm/ephpm base image ships demo files there,
# which would be copied into a fresh named volume)
WORKDIR /var/www/opencart
VOLUME ["/var/www/opencart"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
