# MODX Revolution on ePHPm: replaces Apache + mod_php / nginx + php-fpm.
#   EPHPM_TAG      ephpm/ephpm image tag (default v0.11.3-php8.5)
#   MODX_VERSION   release (default 3.1.1)
ARG EPHPM_TAG=v0.11.3-php8.5
ARG MODX_VERSION=3.1.1

FROM docker.io/library/alpine:3.20 AS src
ARG MODX_VERSION
RUN apk add --no-cache curl unzip
RUN curl -fsSL -o /tmp/m.zip "https://modx.s3.amazonaws.com/releases/${MODX_VERSION}/modx-${MODX_VERSION}-pl.zip" \
    && mkdir /tmp/x && unzip -q /tmp/m.zip -d /tmp/x && mv /tmp/x/modx-* /src

FROM docker.io/ephpm/ephpm:${EPHPM_TAG}
RUN rm -rf /var/www/html
COPY --from=src /src /var/www/html
COPY ephpm.toml /etc/ephpm/ephpm.toml
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN printf '#!/bin/sh\nexec ephpm php "$@"\n' > /usr/local/bin/php && chmod +x /usr/local/bin/php /usr/local/bin/entrypoint.sh
RUN mkdir -p /usr/local/share/modx-core && cp -a /var/www/html/core/. /usr/local/share/modx-core/
WORKDIR /var/www/html
VOLUME ["/var/www/html/core"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
