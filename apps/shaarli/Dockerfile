# Shaarli on ePHPm.
#
# One container replaces nginx + php-fpm + s6 (the shaarli/shaarli image):
# ePHPm serves the static assets, runs index.php (the Slim front controller)
# and keeps PHP sessions in its in-process KV store. Shaarli is flat-file —
# no database anywhere.
#
# Build args:
#   EPHPM_TAG        ephpm/ephpm image tag (default v0.11.3-php8.5)
#   SHAARLI_VERSION  Shaarli release to bake in (default v0.16.9)

ARG EPHPM_TAG=v0.11.3-php8.5
ARG SHAARLI_VERSION=v0.16.9

# ── Stage 1: the "full" release zip (ships vendor/ and the built assets) ─────
FROM docker.io/library/alpine:3.20 AS src
ARG SHAARLI_VERSION
RUN apk add --no-cache curl unzip
RUN curl -fsSL -o /shaarli.zip \
      "https://github.com/shaarli/Shaarli/releases/download/${SHAARLI_VERSION}/shaarli-${SHAARLI_VERSION}-full.zip" \
    && unzip -q /shaarli.zip -d /unpacked && mv /unpacked/Shaarli /src && rm /shaarli.zip \
    # build-time material that the web root does not need
    && cd /src && rm -rf assets doc/md package.json yarn.lock webpack.config.js eslint.config.mjs \
       phpcs.xml phpdoc.dist.xml

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

COPY --from=src /src /var/www/shaarli
COPY ephpm.toml /etc/ephpm/ephpm.toml
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh \
    && mkdir -p /var/www/shaarli/data /var/www/shaarli/cache /var/www/shaarli/pagecache /var/www/shaarli/tmp

WORKDIR /var/www/shaarli
VOLUME ["/var/www/shaarli/data", "/var/www/shaarli/cache"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
