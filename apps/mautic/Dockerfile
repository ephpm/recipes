# Mautic on ePHPm.
#
# One image replaces the official mautic/mautic image (php-apache or php-fpm,
# plus its cron and worker roles): ePHPm serves docroot/ and runs PHP; the
# cron and worker roles are separate services in compose.yml running the
# same image, as in the official examples/basic compose.
#
# Build args:
#   EPHPM_TAG       ephpm/ephpm image tag (default v0.11.3-php8.4)
#   MAUTIC_VERSION  mautic/recommended-project version to create (default 7.2.1)

ARG EPHPM_TAG=v0.11.3-php8.4
ARG MAUTIC_VERSION=7.2.1

# ── Stage 1: composer create-project (what the official Dockerfile does) ─────
# Mautic ships as a Composer project, not a dist archive. The Composer
# scripts (npm ci, patch-package, the asset build) are skipped here and
# replayed in the next two stages, which have the tools they need.
FROM docker.io/library/composer:2 AS build
ARG MAUTIC_VERSION
RUN composer create-project "mautic/recommended-project:${MAUTIC_VERSION}" /src \
        --no-interaction --no-progress --prefer-dist --no-scripts --ignore-platform-reqs

# ── Stage 2: the npm half of the Composer scripts ────────────────────────────
FROM docker.io/library/node:22-bookworm AS node
COPY --from=build /src /src
WORKDIR /src
RUN npm ci --prefer-offline --no-audit --no-fund && npx patch-package

# ── Stage 3: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

# Same location as the official image.
COPY --from=node /src /var/www/html
COPY ephpm.toml /etc/ephpm/
COPY mautic /usr/local/bin/mautic
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
WORKDIR /var/www/html
# The PHP half of the Composer scripts, on the embedded PHP: the official
# image runs `mautic:assets:generate` (combined/minified bundle assets) and
# `assets:install`; Mautic 7's UI additionally needs the Sass build and the
# AssetMapper compile (`var/sass/app.output.css`, `docroot/assets/`).
RUN chmod +x /usr/local/bin/mautic /usr/local/bin/entrypoint.sh \
    && mkdir -p /var/lib/ephpm config var/logs var/cache var/tmp docroot/media/files docroot/media/images \
    && mautic mautic:assets:generate --no-interaction \
    && mautic assets:install --symlink --relative docroot/ --no-interaction \
    && mautic sass:build --no-interaction \
    && mautic asset-map:compile --no-interaction \
    && rm -rf var/cache/* \
    # the official image keeps only these two node_modules at runtime
    && find node_modules -mindepth 1 -maxdepth 1 -not \( -name jquery -or -name vimeo-froogaloop2 \) -exec rm -rf {} + \
    # pristine copies, used by entrypoint.sh to seed empty volumes
    && mkdir -p /usr/local/share/mautic \
    && cp -a config /usr/local/share/mautic/config \
    && cp -a docroot/media /usr/local/share/mautic/media

VOLUME ["/var/www/html/config", "/var/www/html/var/logs", "/var/www/html/docroot/media/files", "/var/www/html/docroot/media/images"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
