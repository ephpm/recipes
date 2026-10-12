# phpSysInfo on ePHPm: replaces Apache/nginx + PHP for the system-information page.
#   EPHPM_TAG            ephpm/ephpm image tag (default v0.11.3-php8.5)
#   PHPSYSINFO_VERSION   release tag (default v3.4.7)
ARG EPHPM_TAG=v0.11.3-php8.5
ARG PHPSYSINFO_VERSION=v3.4.7

FROM docker.io/library/alpine:3.20 AS src
ARG PHPSYSINFO_VERSION
RUN apk add --no-cache curl tar
RUN mkdir -p /src \
    && curl -fsSL "https://github.com/phpsysinfo/phpsysinfo/archive/refs/tags/${PHPSYSINFO_VERSION}.tar.gz" \
       | tar xz --strip-components=1 -C /src \
    && cp /src/phpsysinfo.ini.new /src/phpsysinfo.ini

FROM docker.io/ephpm/ephpm:${EPHPM_TAG}
RUN rm -rf /var/www/html
COPY --from=src /src /var/www/html
COPY ephpm.toml /etc/ephpm/ephpm.toml
WORKDIR /var/www/html
EXPOSE 8080
ENTRYPOINT ["tini", "--", "ephpm", "serve", "--config", "/etc/ephpm/ephpm.toml"]
