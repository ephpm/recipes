# Adminer on ePHPm.
#
# One container replaces `php -S` (the official adminer image runs PHP's
# built-in web server): ePHPm serves index.php / adminer.php and keeps PHP
# sessions in its in-process KV store. Adminer is one PHP file; this image
# adds the designs and plugins from the source tree, like the official one.
#
# Build args:
#   EPHPM_TAG        ephpm/ephpm image tag (default v0.11.3-php8.5)
#   ADMINER_VERSION  Adminer release to bake in (default 6.1.2)

ARG EPHPM_TAG=v0.11.3-php8.5
ARG ADMINER_VERSION=6.1.2

# ── Stage 1: adminer.php (all drivers) + designs/ and plugins/ from the source ──
FROM docker.io/library/alpine:3.20 AS src
ARG ADMINER_VERSION
RUN apk add --no-cache curl tar
RUN mkdir -p /src/plugins-enabled \
    && curl -fsSL "https://github.com/vrana/adminer/releases/download/v${ADMINER_VERSION}/adminer-${ADMINER_VERSION}.php" \
       -o /src/adminer.php \
    && curl -fsSL "https://github.com/vrana/adminer/archive/v${ADMINER_VERSION}.tar.gz" -o /tmp/source.tar.gz \
    && tar xzf /tmp/source.tar.gz -C /src --strip-components=1 \
       "adminer-${ADMINER_VERSION}/designs/" "adminer-${ADMINER_VERSION}/plugins/" \
    && rm /tmp/source.tar.gz

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

# The base image ships ePHPm's E2E fixtures in /var/www/html (phpinfo()
# among them, issues/joomla.md): start from an empty web root.
RUN rm -rf /var/www/html
COPY --from=src /src /var/www/html
COPY index.php plugin-loader.php /var/www/html/
COPY ephpm.toml /etc/ephpm/ephpm.toml
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /var/www/html
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
