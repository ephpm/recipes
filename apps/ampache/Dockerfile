# Ampache on ePHPm.
#
# One container replaces the official image's Apache + mod_php (+ cron +
# supervisord): ePHPm serves public/ and runs PHP; the Subsonic API rewrite
# is handled by front.php. Ampache 8 requires PHP >= 8.5.
#
# Build args:
#   EPHPM_TAG         ephpm/ephpm image tag (default v0.11.3-php8.5)
#   AMPACHE_VERSION   release (default 8.2.2)
#
# The `_all_php8.5` release zip ships vendor/ and the built front end.

ARG EPHPM_TAG=v0.11.3-php8.5
ARG AMPACHE_VERSION=8.2.2

# ── Stage 1: the release zip ─────────────────────────────────────────────────
FROM docker.io/library/alpine:3.20 AS src
ARG AMPACHE_VERSION
RUN apk add --no-cache curl unzip
RUN curl -fsSL -o /tmp/ampache.zip \
        "https://github.com/ampache/ampache/releases/download/${AMPACHE_VERSION}/ampache-${AMPACHE_VERSION}_all_php8.5.zip" \
    && mkdir /src && unzip -q /tmp/ampache.zip -d /src && rm /tmp/ampache.zip \
    && rm -rf /src/docs

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

COPY --from=src /src /app
# ePHPm v0.11.3 does not feed $_SERVER through PHP's input filter, so
# filter_has_var(INPUT_SERVER, …) is always false (issues/ampache.md) and
# Ampache sees an empty client IP: every page is "Access Denied" by its ACL.
# Read $_SERVER directly instead (the build fails if the code changed).
# Remove once ePHPm is fixed.
RUN f=/app/src/Module/System/Core.php \
    && [ "$(grep -c "filter_has_var(INPUT_SERVER, '" "$f")" = 2 ] \
    && sed -i -E "s/filter_has_var\(INPUT_SERVER, '([A-Z_]+)'\)/isset(\$_SERVER['\1'])/g" "$f" \
    && grep -q "isset(\$_SERVER\['REMOTE_ADDR'\])" "$f"
COPY front.php /app/public/ephpm-front.php
COPY php /usr/local/bin/php
COPY ephpm.toml /etc/ephpm/ephpm.toml
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/php /usr/local/bin/entrypoint.sh /app/bin/cli /app/bin/installer \
    # pristine copy, used by entrypoint.sh to seed an empty config volume
    && mkdir -p /usr/local/share/ampache /media \
    && cp -a /app/config /usr/local/share/ampache/config

WORKDIR /app
VOLUME ["/app/config", "/media"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
