# wallabag on ePHPm.
#
# One container replaces the official wallabag/wallabag image's nginx +
# php-fpm pair (supervised by s6): ePHPm serves web/ and runs PHP; the
# Symfony front controller rewrite comes from ephpm.toml.
#
# Build args:
#   EPHPM_TAG         ephpm/ephpm image tag (default v0.11.3-php8.4 — the
#                     official image ships PHP 8.4 and wallabag 2.6 is not
#                     tested upstream on 8.5)
#   WALLABAG_VERSION  wallabag release to bake in (default 2.6.14)

ARG EPHPM_TAG=v0.11.3-php8.4
ARG WALLABAG_VERSION=2.6.14

# ── Stage 1: fetch the release tarball (vendor/ and built assets included) ───
FROM docker.io/library/alpine:3.20 AS src
ARG WALLABAG_VERSION
RUN apk add --no-cache curl tar
RUN curl -fsSL -o /wallabag.tar.gz \
        "https://github.com/wallabag/wallabag/releases/download/${WALLABAG_VERSION}/wallabag-${WALLABAG_VERSION}.tar.gz" \
    && mkdir /unpack && tar xzf /wallabag.tar.gz -C /unpack \
    && mv /unpack/wallabag-* /src && rm -rf /unpack /wallabag.tar.gz \
    # development/test material that is not needed to run the app
    && rm -rf /src/tests /src/docker /src/docker-compose.yml /src/scripts \
              /src/node_modules /src/var/cache/* /src/var/logs/* /src/var/sessions/* \
    && mkdir -p /src/data/db /src/data/assets /src/web/assets/images \
                /src/var/cache /src/var/logs /src/var/sessions

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

COPY --from=src /src /var/www/wallabag
COPY ephpm.toml /etc/ephpm/
COPY wallabag /usr/local/bin/wallabag
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/wallabag /usr/local/bin/entrypoint.sh \
    && mkdir -p /var/lib/ephpm

WORKDIR /var/www/wallabag
VOLUME ["/var/www/wallabag/data", "/var/www/wallabag/web/assets/images"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
