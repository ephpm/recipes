# FOSSBilling on ePHPm: replaces Apache/nginx + php-fpm (+ the cron entry).
#   EPHPM_TAG             ephpm/ephpm image tag (default v0.11.3-php8.5)
#   FOSSBILLING_VERSION   release (default 0.8.8)
ARG EPHPM_TAG=v0.11.3-php8.5
ARG FOSSBILLING_VERSION=0.8.8

FROM docker.io/library/alpine:3.20 AS src
ARG FOSSBILLING_VERSION
RUN apk add --no-cache curl unzip
RUN curl -fsSL -o /tmp/f.zip "https://github.com/FOSSBilling/FOSSBilling/releases/download/${FOSSBILLING_VERSION}/FOSSBilling-${FOSSBILLING_VERSION}.zip" \
    && mkdir /src && unzip -q /tmp/f.zip -d /src && rm /tmp/f.zip

FROM docker.io/ephpm/ephpm:${EPHPM_TAG}
RUN rm -rf /var/www/html
COPY --from=src /src /var/www/html
COPY ephpm.toml /etc/ephpm/ephpm.toml
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN printf '#!/bin/sh\nexec ephpm php "$@"\n' > /usr/local/bin/php && chmod +x /usr/local/bin/php /usr/local/bin/entrypoint.sh \
    && mkdir -p /usr/local/share/fossbilling && cp -a /var/www/html/data /usr/local/share/fossbilling/data
WORKDIR /var/www/html
VOLUME ["/var/www/html/data"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
