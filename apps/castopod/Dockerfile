# Castopod on ePHPm.
#
# One container replaces the official castopod/castopod image (FrankenPHP +
# a supercronic cron, supervised by s6-overlay): ePHPm serves public/ and
# runs PHP; the CodeIgniter 4 front-controller rewrite comes from ephpm.toml.
# The scheduled tasks (`spark tasks:run`, every minute) run in a second
# service in compose.yml using the same image.
#
# Build args:
#   EPHPM_TAG          ephpm/ephpm image tag (default v0.11.3-php8.4 — the official image ships PHP 8.4)
#   CASTOPOD_VERSION   Castopod release to bake in (default 1.15.5)
#   CASTOPOD_BUNDLE    URL of that release's "Castopod Package (tar.gz)" from
#                      https://code.castopod.org/adaures/castopod/-/releases
#                      (the upload path carries a per-release hash, so it is pinned here)

ARG EPHPM_TAG=v0.11.3-php8.4
ARG CASTOPOD_VERSION=1.15.5
ARG CASTOPOD_BUNDLE=https://code.castopod.org/-/project/2/uploads/d5a21b906eb7644bd05dfeb81fe60eb2/castopod-1.15.5.tar.gz

# ── Stage 1: fetch the release bundle (vendor/ and built assets included) ────
FROM docker.io/library/alpine:3.20 AS src
ARG CASTOPOD_BUNDLE
RUN apk add --no-cache curl tar
RUN curl -fsSL -o /castopod.tar.gz "${CASTOPOD_BUNDLE}" \
    && mkdir /unpack && tar xzf /castopod.tar.gz -C /unpack \
    && mv /unpack/castopod /src && rm -rf /unpack /castopod.tar.gz \
    && mkdir -p /src/writable/cache /src/writable/logs /src/writable/session \
                /src/writable/uploads /src/writable/temp /src/public/media

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

# Same location as the official image.
COPY --from=src /src /app
COPY ephpm.toml /etc/ephpm/
COPY spark /usr/local/bin/spark
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
WORKDIR /app
RUN chmod +x /usr/local/bin/spark /usr/local/bin/entrypoint.sh \
    && mkdir -p /var/lib/ephpm \
    # pristine copies, used by entrypoint.sh to seed empty volumes
    && mkdir -p /usr/local/share/castopod \
    && cp -a writable /usr/local/share/castopod/writable \
    && cp -a public/media /usr/local/share/castopod/media

VOLUME ["/app/public/media", "/app/writable"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
