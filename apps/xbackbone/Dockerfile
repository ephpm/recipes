# XBackBone on ePHPm: replaces Apache/nginx + php-fpm for the XBackBone file/screenshot host.
#   EPHPM_TAG           ephpm/ephpm image tag (default v0.11.3-php8.5)
#   XBACKBONE_VERSION   release (default 3.8.2)
ARG EPHPM_TAG=v0.11.3-php8.5
ARG XBACKBONE_VERSION=3.8.2

FROM docker.io/library/alpine:3.20 AS src
ARG XBACKBONE_VERSION
RUN apk add --no-cache curl unzip
RUN curl -fsSL -o /tmp/x.zip "https://github.com/SergiX44/XBackBone/releases/download/${XBACKBONE_VERSION}/release-v${XBACKBONE_VERSION}.zip" \
    && mkdir /src && unzip -q /tmp/x.zip -d /src && rm /tmp/x.zip

FROM docker.io/ephpm/ephpm:${EPHPM_TAG}
RUN rm -rf /var/www/html
COPY --from=src /src /var/www/html
COPY ephpm.toml /etc/ephpm/ephpm.toml
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh \
    && mkdir -p /var/www/html/storage \
WORKDIR /var/www/html
VOLUME ["/var/www/html/storage", "/var/www/html/resources/database"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
