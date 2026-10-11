# MediaWiki on ePHPm.
#
# One container replaces Apache + mod_php (the mediawiki:apache image):
# ePHPm serves the files and runs PHP; the maintenance scripts (installer,
# updater, jobs) run on the embedded PHP CLI.
#
# Build args:
#   EPHPM_TAG          ephpm/ephpm image tag (default v0.11.3-php8.5)
#   MEDIAWIKI_VERSION  MediaWiki release to bake in (default 1.46.2)

ARG EPHPM_TAG=v0.11.3-php8.5
ARG MEDIAWIKI_VERSION=1.46.2

# ── Stage 1: the release tarball (vendor/ included) ─────────────────────────
FROM docker.io/library/alpine:3.20 AS src
ARG MEDIAWIKI_VERSION
RUN apk add --no-cache curl tar
RUN mkdir -p /src \
    && major="${MEDIAWIKI_VERSION%.*}" \
    && curl -fsSL "https://releases.wikimedia.org/mediawiki/${major}/mediawiki-${MEDIAWIKI_VERSION}.tar.gz" \
       | tar xz --strip-components=1 -C /src \
    && rm -rf /src/tests /src/docs /src/CODE_OF_CONDUCT.md /src/bundlesize.config.json /src/jsdoc.json

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

COPY --from=src /src /var/www/html
COPY php /usr/local/bin/php
COPY ephpm.toml /etc/ephpm/ephpm.toml
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/php /usr/local/bin/entrypoint.sh \
    && mkdir -p /var/www/config /var/www/data /var/www/html/images \
    # pristine images/ (its .htaccess and README), to seed an empty volume
    && cp -a /var/www/html/images /usr/local/share/mediawiki-images

WORKDIR /var/www/html
VOLUME ["/var/www/html/images", "/var/www/config", "/var/www/data"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
