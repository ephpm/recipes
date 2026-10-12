# phpIPAM on ePHPm: replaces Apache + mod_php (or nginx + php-fpm) + cron.
#   EPHPM_TAG        ephpm/ephpm image tag (default v0.11.3-php8.5)
#   PHPIPAM_VERSION  release (default 1.8.3)
ARG EPHPM_TAG=v0.11.3-php8.5
ARG PHPIPAM_VERSION=1.8.3

FROM docker.io/library/alpine:3.20 AS src
ARG PHPIPAM_VERSION
RUN apk add --no-cache curl tar
# The release tarball (not the git archive) includes vendored libraries.
RUN mkdir -p /src \
    && curl -fsSL "https://github.com/phpipam/phpipam/releases/download/v${PHPIPAM_VERSION}/phpipam-v${PHPIPAM_VERSION}.tgz" \
       | tar xz --strip-components=1 -C /src

FROM docker.io/ephpm/ephpm:${EPHPM_TAG}
RUN rm -rf /var/www/html
COPY --from=src /src /var/www/html
COPY ephpm.toml /etc/ephpm/ephpm.toml
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN printf '#!/bin/sh\nexec ephpm php "$@"\n' > /usr/local/bin/php && chmod +x /usr/local/bin/php /usr/local/bin/entrypoint.sh \
    && mkdir -p /usr/local/share/phpipam && cp -a /var/www/html/app/admin/import-export/upload /usr/local/share/phpipam/ 2>/dev/null || true
WORKDIR /var/www/html
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
