# RSS-Bridge on ePHPm.
#
# One container replaces the rssbridge/rss-bridge image (nginx + php-fpm):
# ePHPm serves the files and runs PHP. No database, no Composer dependencies.
#
# Build args:
#   EPHPM_TAG          ephpm/ephpm image tag (default v0.11.3-php8.5)
#   RSSBRIDGE_VERSION  RSS-Bridge release tag (default 2025-08-05, the latest
#                      tagged release; the official image builds from master —
#                      pass a branch or commit archive name to follow it)

ARG EPHPM_TAG=v0.11.3-php8.5
ARG RSSBRIDGE_VERSION=2025-08-05

FROM docker.io/library/alpine:3.20 AS src
ARG RSSBRIDGE_VERSION
RUN apk add --no-cache curl tar
RUN mkdir /src \
    && curl -fsSL "https://github.com/RSS-Bridge/rss-bridge/archive/${RSSBRIDGE_VERSION}.tar.gz" \
       | tar xz --strip-components=1 -C /src \
    && rm -rf /src/tests /src/.github /src/contrib /src/docs /src/config /src/docker-* /src/Dockerfile

FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

COPY --from=src /src /app
COPY ephpm.toml /etc/ephpm/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh \
    && mkdir -p /var/lib/ephpm /config /app/cache

WORKDIR /app
VOLUME ["/config"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
