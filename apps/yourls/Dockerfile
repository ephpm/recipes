# YOURLS on ePHPm.
#
# One container replaces Apache + mod_php (the yourls:apache image): ePHPm
# serves the files and runs PHP, with the .htaccess rewrite to
# yourls-loader.php expressed as [server] fallback.
#
# Build args:
#   EPHPM_TAG       ephpm/ephpm image tag (default v0.11.3-php8.5)
#   YOURLS_VERSION  YOURLS release to bake in (default 1.10.6)

ARG EPHPM_TAG=v0.11.3-php8.5
ARG YOURLS_VERSION=1.10.6

# ── Stage 1: the release tarball (vendor/ is committed under includes/) ──────
FROM docker.io/library/alpine:3.20 AS src
ARG YOURLS_VERSION
RUN apk add --no-cache curl tar
RUN mkdir -p /src \
    && curl -fsSL "https://github.com/YOURLS/YOURLS/archive/refs/tags/${YOURLS_VERSION}.tar.gz" \
       | tar xz --strip-components=1 -C /src \
    && rm -rf /src/.github /src/composer.json /src/composer.lock

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

# The base image ships ePHPm's E2E fixtures in /var/www/html (phpinfo()
# among them, issues/joomla.md): start from an empty web root.
RUN rm -rf /var/www/html
COPY --from=src /src /var/www/html
COPY config.php /var/www/html/user/config.php
COPY ephpm.toml /etc/ephpm/ephpm.toml
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh \
    && mkdir -p /var/lib/ephpm \
    # pristine copy, used by entrypoint.sh to seed an empty user/ volume
    && mkdir -p /usr/local/share/yourls \
    && cp -a /var/www/html/user /usr/local/share/yourls/user

WORKDIR /var/www/html
VOLUME ["/var/www/html/user"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
