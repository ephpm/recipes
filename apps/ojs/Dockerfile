# Open Journal Systems (OJS) on ePHPm.
#
# One container replaces the official pkp/ojs image (php-apache with
# mod_rewrite + cron): ePHPm serves the application root and runs PHP. OJS
# routes by PATH_INFO (`/index.php/<journal>/<page>`), which Apache provides
# with `AcceptPathInfo On`; ePHPm does not, so a small front controller
# (front.php) derives it from the request URI before handing over to OJS.
#
# Build args:
#   EPHPM_TAG    ephpm/ephpm image tag (default v0.11.3-php8.4)
#   OJS_VERSION  OJS release to bake in (default 3.5.0-4)

ARG EPHPM_TAG=v0.11.3-php8.4
ARG OJS_VERSION=3.5.0-4

# ── Stage 1: fetch the release tarball (vendor/ and built assets included) ───
FROM docker.io/library/alpine:3.20 AS src
ARG OJS_VERSION
RUN apk add --no-cache curl tar
RUN curl -fsSL -o /ojs.tar.gz "https://pkp.sfu.ca/ojs/download/ojs-${OJS_VERSION}.tar.gz" \
    && mkdir /src && tar xzf /ojs.tar.gz --strip-components=1 -C /src && rm /ojs.tar.gz \
    && rm -rf /src/.github /src/cypress /src/lib/pkp/cypress /src/lib/pkp/tests

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

# Same locations as the official image: app in /var/www/html, uploads in /var/www/files.
COPY --from=src /src /var/www/html
COPY front.php /var/www/html/ephpm-front.php
COPY ephpm.toml /etc/ephpm/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
WORKDIR /var/www/html
RUN chmod +x /usr/local/bin/entrypoint.sh \
    && mkdir -p /var/lib/ephpm /var/www/files cache \
    # pristine copy of public/ (journal logos, uploads), used to seed an empty volume
    && cp -a public /usr/local/share/ojs-public

VOLUME ["/var/www/files", "/var/www/html/public"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
