# Drupal on ePHPm.
#
# One container replaces the official `drupal` image's Apache + mod_php:
# ePHPm serves web/ and runs PHP; Drush (added to the project) runs on the
# embedded PHP.
#
# The project is built the way the official image builds it — `composer
# create-project drupal/recommended-project` into /opt/drupal, web root
# /opt/drupal/web — plus drush/drush, which the entrypoint uses for the
# unattended install. For your own site replace the create-project line with
# `COPY composer.json composer.lock ./` + `composer install`.
#
# Build args:
#   EPHPM_TAG       ephpm/ephpm image tag (default v0.11.3-php8.5)
#   DRUPAL_VERSION  drupal/recommended-project version (default 11.4.9)
#   DRUSH_VERSION   drush/drush constraint (default ^13)

ARG EPHPM_TAG=v0.11.3-php8.5
ARG DRUPAL_VERSION=11.4.9
ARG DRUSH_VERSION=^13

# ── Stage 1: Composer (the scaffold plugin writes web/index.php, .htaccess, …) ─
FROM docker.io/library/composer:2 AS vendor
ARG DRUPAL_VERSION
ARG DRUSH_VERSION
ENV COMPOSER_ALLOW_SUPERUSER=1
WORKDIR /opt/drupal
RUN composer create-project --no-interaction --no-progress --ignore-platform-reqs \
        "drupal/recommended-project:${DRUPAL_VERSION}" ./ \
    && composer require --no-interaction --no-progress --ignore-platform-reqs --update-no-dev \
        "drush/drush:${DRUSH_VERSION}" \
    && rm -rf /tmp/* /root/.composer

# ── Stage 2: the runtime image ───────────────────────────────────────────────
FROM docker.io/ephpm/ephpm:${EPHPM_TAG}

COPY --from=vendor /opt/drupal /opt/drupal
COPY ephpm.toml /etc/ephpm/ephpm.toml
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
# `php` on PATH (and DRUSH_PHP): Drush re-invokes PHP for batch work and
# sub-processes; PHP_BINARY is `ephpm` here, so point it at `ephpm php`.
RUN printf '#!/bin/sh\nexec ephpm php "$@"\n' > /usr/local/bin/php \
    && chmod +x /usr/local/bin/php /usr/local/bin/entrypoint.sh \
    # pristine sites/ to seed the volume (settings.php, files/ live there)
    && cp -a /opt/drupal/web/sites /usr/local/share/drupal-sites \
    && mkdir -p /opt/drupal/private /var/lib/ephpm \
    # the base image's E2E fixtures (issues/joomla.md) are not needed here
    && rm -rf /var/www/html
ENV PATH=/opt/drupal/vendor/bin:${PATH} \
    DRUSH_PHP=/usr/local/bin/php

WORKDIR /opt/drupal
VOLUME ["/opt/drupal/web/sites", "/opt/drupal/private"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
