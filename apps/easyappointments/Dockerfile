# Easy!Appointments on ePHPm.
#
# One container replaces the upstream nginx + php-fpm pair (docker-compose.yml)
# and the official php:8.2-apache image: ePHPm serves the assets, runs PHP and
# answers the front-controller rewrite from ephpm.toml.
#
# Build args:
#   EPHPM_TAG   ephpm/ephpm image tag (default v0.11.3-php8.5)
#   EA_VERSION  Easy!Appointments release to bake in (default 1.6.0)

ARG EPHPM_TAG=v0.11.3-php8.5
ARG EA_VERSION=1.6.0

# ── Stage 1: fetch the release zip (ships vendor/ and the built assets) ──────
FROM docker.io/library/alpine:3.20 AS src
ARG EA_VERSION
RUN apk add --no-cache curl unzip
RUN curl -fsSL -o /ea.zip \
        "https://github.com/alextselegidis/easyappointments/releases/download/${EA_VERSION}/easyappointments-${EA_VERSION}.zip" \
    && mkdir /src && unzip -q /ea.zip -d /src && rm /ea.zip \
    && mkdir -p /src/storage/backups /src/storage/cache /src/storage/logs \
                /src/storage/sessions /src/storage/uploads

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

COPY --from=src /src /var/www/html
COPY ephpm.toml /etc/ephpm/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh \
    && mkdir -p /var/lib/ephpm \
    # pristine copy, used by entrypoint.sh to seed an empty storage volume
    && mkdir -p /usr/local/share/easyappointments \
    && cp -a /var/www/html/storage /usr/local/share/easyappointments/storage

VOLUME ["/var/www/html/storage"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
