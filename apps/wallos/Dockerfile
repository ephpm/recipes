# Wallos on ePHPm.
#
# One container replaces the official bellamy/wallos image's nginx + php-fpm
# (+ crond): ePHPm serves the files and runs PHP; Wallos's cron jobs run in a
# sidecar from the same image. The database is Wallos's own SQLite file
# (PHP's sqlite3 extension — no database server at all).
#
# Build args:
#   EPHPM_TAG        ephpm/ephpm image tag (default v0.11.3-php8.5)
#   WALLOS_VERSION   Wallos release tag to bake in (default v5.8.3)

ARG EPHPM_TAG=v0.11.3-php8.5
ARG WALLOS_VERSION=v5.8.3

# ── Stage 1: fetch the release ───────────────────────────────────────────────
FROM docker.io/library/alpine:3.20 AS src
ARG WALLOS_VERSION
RUN apk add --no-cache curl tar
RUN mkdir /src \
    && curl -fsSL "https://github.com/ellite/Wallos/archive/refs/tags/${WALLOS_VERSION}.tar.gz" \
       | tar xz --strip-components=1 -C /src \
    && rm -rf /src/tests /src/dev /src/.github /src/screenshots /src/Dockerfile \
       /src/docker-compose.yaml /src/nginx.conf /src/nginx.default.conf /src/startup.sh

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

# cron for the scheduler sidecar (Wallos's upstream image runs dcron)
RUN apt-get update \
    && apt-get install -y --no-install-recommends cron \
    && rm -rf /var/lib/apt/lists/*

COPY --from=src /src /var/www/html
COPY ephpm.toml /etc/ephpm/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
WORKDIR /var/www/html
RUN chmod +x /usr/local/bin/entrypoint.sh \
    # Wallos's own crontab, with `php` replaced by the embedded PHP and the
    # output sent to the container log
    && { sed -e 's#/usr/local/bin/php#cd /var/www/html \&\& /usr/local/bin/ephpm php#' \
             -e 's#>> /var/log/cron/[a-z]*\.log 2>&1#>> /proc/1/fd/1 2>\&1#' \
             /var/www/html/cronjobs; echo; } | crontab - \
    && rm /var/www/html/cronjobs \
    && mkdir -p /var/www/html/images/uploads/logos/avatars \
    # pristine copies, used by entrypoint.sh to seed empty volumes
    && mkdir -p /usr/local/share/wallos \
    && cp -a /var/www/html/db /usr/local/share/wallos/db \
    && cp -a /var/www/html/images/uploads/logos /usr/local/share/wallos/logos

VOLUME ["/var/www/html/db", "/var/www/html/images/uploads/logos"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
