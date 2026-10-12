# Tiny File Manager on ePHPm.
#
# One container replaces the upstream image's `php -S` (PHP's built-in
# development server) with a production HTTP server. The single-file app is
# the web root; the files it manages live in /data, outside the web root,
# so nothing uploaded through it can be fetched or executed directly.
#
# Build args:
#   EPHPM_TAG     ephpm/ephpm image tag (default v0.11.3-php8.5)
#   TFM_VERSION   Tiny File Manager release tag (default 2.6)

ARG EPHPM_TAG=v0.11.3-php8.5
ARG TFM_VERSION=2.6

# ── Stage 1: the release source ──────────────────────────────────────────────
FROM docker.io/library/alpine:3.20 AS src
ARG TFM_VERSION
RUN apk add --no-cache curl tar
RUN mkdir -p /src \
    && curl -fsSL "https://github.com/prasathmani/tinyfilemanager/archive/refs/tags/${TFM_VERSION}.tar.gz" \
       | tar xz --strip-components=1 -C /src

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

COPY --from=src /src/tinyfilemanager.php /app/index.php
COPY --from=src /src/translation.json /app/translation.json
COPY ephpm.toml /etc/ephpm/ephpm.toml
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh \
    && mkdir -p /data /etc/tinyfilemanager \
    # config.php is generated from the environment on every start
    && ln -s /etc/tinyfilemanager/config.php /app/config.php

WORKDIR /app
VOLUME ["/data"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
