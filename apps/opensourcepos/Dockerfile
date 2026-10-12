# Open Source Point of Sale on ePHPm.
#
# One container replaces the upstream image's Apache + mod_php: ePHPm serves
# public/ and runs PHP; CodeIgniter 4's front-controller rewrite is
# `[server] fallback`. The release zip ships vendor/ and the built assets,
# so there is no Composer or Node stage.
#
# Build args:
#   EPHPM_TAG       ephpm/ephpm image tag (default v0.11.3-php8.4 — upstream
#                   supports PHP 8.2 to 8.4)
#   OSPOS_VERSION   release tag (default 3.4.2)
#   OSPOS_ASSET     release asset file name (it carries a commit hash)

ARG EPHPM_TAG=v0.11.3-php8.4
ARG OSPOS_VERSION=3.4.2
ARG OSPOS_ASSET=opensourcepos.3.4.2.cb5e2a.zip

# ── Stage 1: the release zip ─────────────────────────────────────────────────
FROM docker.io/library/alpine:3.20 AS src
ARG OSPOS_VERSION
ARG OSPOS_ASSET
RUN apk add --no-cache curl unzip
RUN curl -fsSL -o /tmp/ospos.zip \
        "https://github.com/opensourcepos/opensourcepos/releases/download/${OSPOS_VERSION}/${OSPOS_ASSET}" \
    && mkdir /src && unzip -q /tmp/ospos.zip -d /src && rm /tmp/ospos.zip \
    && rm -rf /src/tests /src/docker /src/Dockerfile /src/docker-compose*.yml /src/app/Database/Dockerfile
# The release zip has no `spark` (the CLI entry point); take it from the tag.
RUN curl -fsSL -o /src/spark "https://raw.githubusercontent.com/opensourcepos/opensourcepos/${OSPOS_VERSION}/spark"

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

COPY --from=src /src /app
# ePHPm v0.11.3 turns an exit() inside an exception handler into a bare 500
# and discards the rendered page (issues/opensourcepos.md), and CodeIgniter
# 4's ExceptionHandler::handle() ends with exit($exitCode) — so every 404 and
# error page would be a blank 500. Exit only on the CLI (where the exit code
# matters); on the web the handler returns and the page is sent. The grep
# makes a CodeIgniter release that changes this code fail the build instead
# of shipping unpatched. Remove once ePHPm is fixed.
RUN f=/app/vendor/codeigniter4/framework/system/Debug/ExceptionHandler.php \
    && [ "$(grep -c "if (ENVIRONMENT !== 'testing') {" "$f")" = 2 ] \
    && sed -i "s/if (ENVIRONMENT !== 'testing') {/if (ENVIRONMENT !== 'testing' \&\& is_cli()) {/" "$f"
COPY php /usr/local/bin/php
COPY ephpm.toml /etc/ephpm/ephpm.toml
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/php /usr/local/bin/entrypoint.sh \
    # pristine copies, used by entrypoint.sh to seed empty volumes
    && mkdir -p /usr/local/share/ospos \
    && cp -a /app/writable /app/public/uploads /app/.env /usr/local/share/ospos/

WORKDIR /app
VOLUME ["/app/writable", "/app/public/uploads"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
