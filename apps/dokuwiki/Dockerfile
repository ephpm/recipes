# DokuWiki on ePHPm.
#
# One container replaces Apache/nginx + php-fpm: ePHPm serves doku.php and
# the static assets and keeps PHP sessions in its in-process KV store.
# DokuWiki is flat-file — pages, media and config are files in the volumes.
#
# Build args:
#   EPHPM_TAG         ephpm/ephpm image tag (default v0.11.3-php8.5)
#   DOKUWIKI_VERSION  DokuWiki release to bake in (default 2026-07-14c)

ARG EPHPM_TAG=v0.11.3-php8.5
ARG DOKUWIKI_VERSION=2026-07-14c

# ── Stage 1: the release tarball (vendor/ included) ─────────────────────────
FROM docker.io/library/alpine:3.20 AS src
ARG DOKUWIKI_VERSION
RUN apk add --no-cache curl tar
RUN mkdir -p /src \
    && curl -fsSL "https://github.com/dokuwiki/dokuwiki/releases/download/release-${DOKUWIKI_VERSION}/dokuwiki-${DOKUWIKI_VERSION}.tgz" \
       | tar xz --strip-components=1 -C /src \
    && rm -f /src/SECURITY.md /src/.htaccess.dist

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

COPY --from=src /src /var/www/html
COPY ephpm.toml /etc/ephpm/ephpm.toml
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh \
    # pristine copies, used by entrypoint.sh to seed empty volumes
    && mkdir -p /usr/local/share/dokuwiki \
    && cp -a /var/www/html/data /var/www/html/conf /var/www/html/lib/plugins /var/www/html/lib/tpl /usr/local/share/dokuwiki/

WORKDIR /var/www/html
VOLUME ["/var/www/html/data", "/var/www/html/conf", "/var/www/html/lib/plugins", "/var/www/html/lib/tpl"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
