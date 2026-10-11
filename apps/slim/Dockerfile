# Slim 4 on ePHPm — the official Slim-Skeleton.
#
# Serves the skeleton in per-request mode, or in persistent worker mode
# through ePHPm's generic PSR-15 adapter (ephpm/psr15-worker) with
# compose.worker.yml. For your own Slim/Mezzio/any-PSR-15 app replace the
# `create-project` line with `COPY . /app` + `composer install` and adapt
# worker-bootstrap.php to return your RequestHandlerInterface.
#
# Build args:
#   EPHPM_TAG      ephpm/ephpm image tag (default v0.11.3-php8.5)
#   SLIM_VERSION   slim/slim-skeleton version constraint (default ^4.0)

ARG EPHPM_TAG=v0.11.3-php8.5
ARG SLIM_VERSION=^4.0

FROM docker.io/library/composer:2 AS vendor
ARG SLIM_VERSION
RUN composer create-project --no-interaction --prefer-dist --no-dev --no-scripts \
        --ignore-platform-reqs slim/slim-skeleton /app "${SLIM_VERSION}"
WORKDIR /app
# PSR-15 worker adapter (+ its ephpm/worker base; Composer does not resolve
# VCS repositories transitively, so both repos are declared). Repository
# type `git` (plain clone) rather than `vcs`, which would use the GitHub API
# and its anonymous rate limit.
RUN composer config repositories.ephpm-psr15 git https://github.com/ephpm/psr15-worker.git \
    && composer config repositories.ephpm-worker git https://github.com/ephpm/php-worker.git \
    && composer config minimum-stability dev && composer config prefer-stable true \
    && composer require --no-interaction --no-scripts --update-no-dev --ignore-platform-reqs \
        ephpm/psr15-worker:^0.1

FROM docker.io/ephpm/ephpm:${EPHPM_TAG}
COPY --from=vendor /app /app
COPY worker-bootstrap.php /app/worker-bootstrap.php
COPY ephpm.toml ephpm.worker.toml /etc/ephpm/
WORKDIR /app
RUN mkdir -p var/cache logs
ENV EPHPM_WORKER_BOOTSTRAP=/app/worker-bootstrap.php

EXPOSE 8080
CMD ["sh", "-c", "exec ephpm serve --config ${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"]
