# Typecho on ePHPm.
#
# One container replaces nginx + php-fpm (the joyqi/typecho images): ePHPm
# serves the files and runs PHP.
#
# Build args:
#   EPHPM_TAG        ephpm/ephpm image tag (default v0.11.3-php8.5)
#   TYPECHO_VERSION  Typecho release (default 1.3.0)

ARG EPHPM_TAG=v0.11.3-php8.5
ARG TYPECHO_VERSION=1.3.0

FROM docker.io/library/alpine:3.20 AS src
ARG TYPECHO_VERSION
RUN apk add --no-cache curl unzip
RUN curl -fsSL -o /typecho.zip "https://github.com/typecho/typecho/releases/download/v${TYPECHO_VERSION}/typecho.zip" \
    && mkdir /src && unzip -q /typecho.zip -d /src

FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

COPY --from=src /src /app
COPY ephpm.toml /etc/ephpm/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
# config.inc.php (written by the installer) is kept in the data volume and
# copied into place by entrypoint.sh — not symlinked: the file derives the
# site root from dirname(__FILE__).
RUN chmod +x /usr/local/bin/entrypoint.sh \
    && mkdir -p /var/lib/ephpm /data /app/usr/uploads

WORKDIR /app
VOLUME ["/data", "/app/usr/uploads"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
