# Directory Lister on ePHPm.
#
# One container replaces the usual Apache/nginx + php-fpm setup: ePHPm serves
# Directory Lister's front controller and runs PHP. The listed files live in
# a separate volume (/data, FILES_PATH), so downloads go through Directory
# Lister's own `?file=` handler and the application code is never listed.
#
# Build args:
#   EPHPM_TAG   ephpm/ephpm image tag (default v0.11.3-php8.5)
#   DL_VERSION  Directory Lister release (default 5.7.0)

ARG EPHPM_TAG=v0.11.3-php8.5
ARG DL_VERSION=5.7.0

# ── Stage 1: the release package (vendor/ and built assets included) ───────
FROM docker.io/library/alpine:3.20 AS src
ARG DL_VERSION
RUN apk add --no-cache curl tar
RUN mkdir -p /src \
    && curl -fsSL "https://github.com/DirectoryLister/DirectoryLister/releases/download/${DL_VERSION}/DirectoryLister-${DL_VERSION}.tar.gz" \
       | tar xz -C /src \
    && rm -f /src/screenshot.png

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

# The base image ships ePHPm's E2E fixtures in /var/www/html (phpinfo()
# among them, issues/joomla.md): start from an empty web root.
RUN rm -rf /var/www/html
COPY --from=src /src /var/www/html
COPY ephpm.toml /etc/ephpm/ephpm.toml
RUN mkdir -p /data /var/www/html/app/cache

# Directory Lister reads its configuration from the environment (or a .env
# next to index.php); see https://docs.directorylister.com/configuration
ENV FILES_PATH=/data

WORKDIR /var/www/html
VOLUME ["/data"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "ephpm", "serve", "--config", "/etc/ephpm/ephpm.toml"]
