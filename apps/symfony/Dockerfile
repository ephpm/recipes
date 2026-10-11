# Symfony on ePHPm — the official Symfony Demo application.
#
# Builds `symfony/symfony-demo` (a complete blog with Doctrine, security,
# forms, AssetMapper) and serves it with ePHPm in per-request mode.
# For your own application replace the `create-project` line with
# `COPY . /app` + `composer install`.
#
# Build args:
#   EPHPM_TAG     ephpm/ephpm image tag (default v0.11.3-php8.5)
#   DEMO_VERSION  symfony/symfony-demo version constraint (default ^2.0)

ARG EPHPM_TAG=v0.11.3-php8.5
ARG DEMO_VERSION=^2.0

# ── Stage 1: Composer (runs the demo's post-install scripts: importmap,
#    sass build, assets:install — they need a PHP, so they run here) ─────────
FROM docker.io/library/composer:2 AS vendor
ARG DEMO_VERSION
ENV APP_ENV=prod
# dev dependencies stay: the demo's fixtures (DoctrineFixturesBundle) are
# dev-only and the entrypoint loads them with --env=dev on first start.
RUN composer create-project --no-interaction --prefer-dist \
        symfony/symfony-demo /app "${DEMO_VERSION}"
WORKDIR /app
# Doctrine's pdo_mysql / pdo_sqlite drivers are compiled into ePHPm.
RUN rm -rf var/cache/* var/log/* data/database.sqlite .env.local

# ── Stage 2: runtime ─────────────────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}
COPY --from=vendor /app /app
COPY ephpm.toml /etc/ephpm/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
WORKDIR /app
ENV APP_ENV=prod \
    APP_DEBUG=0 \
    APP_SECRET=change-me-please-32-chars-minimum \
    DATABASE_URL="sqlite:////app/data/database.sqlite" \
    MAILER_DSN=null://null \
    DEFAULT_URI=http://localhost:8080
RUN chmod +x /usr/local/bin/entrypoint.sh \
    && mkdir -p /var/lib/ephpm /app/data /app/var \
    && ephpm php bin/console cache:warmup --env=prod

VOLUME ["/app/data", "/app/var"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
