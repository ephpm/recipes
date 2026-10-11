# Roundcube Webmail on ePHPm.
#
# One container replaces Apache + mod_php (the roundcube/roundcubemail image):
# ePHPm serves public_html/ (index.php + the static.php asset endpoint) and
# runs PHP; bin/initdb.sh and friends run on the embedded PHP CLI. Roundcube
# needs an IMAP/SMTP server of yours — the compose files ship a throwaway
# test mail server so the stack runs out of the box.
#
# Build args:
#   EPHPM_TAG          ephpm/ephpm image tag (default v0.11.3-php8.5)
#   ROUNDCUBE_VERSION  Roundcube release to bake in (default 1.7.4)

ARG EPHPM_TAG=v0.11.3-php8.5
ARG ROUNDCUBE_VERSION=1.7.4

# ── Stage 1: the "complete" release tarball (vendor/ and plugins included) ──
FROM docker.io/library/alpine:3.20 AS src
ARG ROUNDCUBE_VERSION
RUN apk add --no-cache curl tar
RUN mkdir -p /src \
    && curl -fsSL "https://github.com/roundcube/roundcubemail/releases/download/${ROUNDCUBE_VERSION}/roundcubemail-${ROUNDCUBE_VERSION}-complete.tar.gz" \
       | tar xz --strip-components=1 -C /src \
    # the web installer is disabled by config and its entry point is not needed
    && rm -f /src/public_html/installer.php /src/public_html/.htaccess \
    && rm -rf /src/installer /src/docs /src/CHANGELOG.md /src/Makefile

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

# The base image ships ePHPm's own test fixtures in /var/www/html (phpinfo()
# among them, see issues/joomla.md); start from an empty directory.
RUN rm -rf /var/www/html
COPY --from=src /src /var/www/html
COPY php /usr/local/bin/php
COPY ephpm.toml /etc/ephpm/ephpm.toml
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/php /usr/local/bin/entrypoint.sh /var/www/html/bin/*.sh \
    && mkdir -p /var/roundcube/config /var/roundcube/db /tmp/roundcube-temp /var/www/html/logs

WORKDIR /var/www/html
VOLUME ["/var/roundcube"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
