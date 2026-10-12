# PostfixAdmin on ePHPm: replaces the Apache/nginx + php-fpm host in front of
# PostfixAdmin (the web UI for Postfix/Dovecot virtual domains and mailboxes).
#   EPHPM_TAG              ephpm/ephpm image tag (default v0.11.3-php8.5)
#   POSTFIXADMIN_VERSION   release tag (default 4.0.5)
ARG EPHPM_TAG=v0.11.3-php8.5
ARG POSTFIXADMIN_VERSION=4.0.5

FROM docker.io/library/alpine:3.20 AS src
ARG POSTFIXADMIN_VERSION
RUN apk add --no-cache curl tar
RUN mkdir -p /src \
    && curl -fsSL "https://github.com/postfixadmin/postfixadmin/archive/refs/tags/v${POSTFIXADMIN_VERSION}.tar.gz" \
       | tar xz --strip-components=1 -C /src

FROM docker.io/library/composer:2 AS vendor
WORKDIR /app
COPY --from=src /src /app
RUN composer install --no-dev --no-interaction --prefer-dist --ignore-platform-reqs --optimize-autoloader --no-progress

FROM docker.io/ephpm/ephpm:${EPHPM_TAG}
COPY --from=vendor /app /app
COPY ephpm.toml /etc/ephpm/ephpm.toml
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN printf '#!/bin/sh\nexec ephpm php "$@"\n' > /usr/local/bin/php && chmod +x /usr/local/bin/php /usr/local/bin/entrypoint.sh \
    && mkdir -p /app/templates_c && chmod 777 /app/templates_c
WORKDIR /app
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
