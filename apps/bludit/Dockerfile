# Bludit on ePHPm: replaces Apache + mod_php / nginx + php-fpm. Flat-file CMS.
#   EPHPM_TAG        ephpm/ephpm image tag (default v0.11.3-php8.5)
#   BLUDIT_VERSION   release tag (default 3.22.0)
ARG EPHPM_TAG=v0.11.3-php8.5
ARG BLUDIT_VERSION=3.22.0

FROM docker.io/library/alpine:3.20 AS src
ARG BLUDIT_VERSION
RUN apk add --no-cache curl tar
RUN mkdir -p /src \
    && curl -fsSL "https://github.com/bludit/bludit/archive/refs/tags/${BLUDIT_VERSION}.tar.gz" \
       | tar xz --strip-components=1 -C /src \
    && rm -rf /src/.github /src/.htaccess

FROM docker.io/ephpm/ephpm:${EPHPM_TAG}
RUN rm -rf /var/www/html
COPY --from=src /src /var/www/html
COPY ephpm.toml /etc/ephpm/ephpm.toml
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh \
    && mkdir -p /usr/local/share/bludit \
    && cp -a /var/www/html/bl-content /usr/local/share/bludit/bl-content
WORKDIR /var/www/html
VOLUME ["/var/www/html/bl-content"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
