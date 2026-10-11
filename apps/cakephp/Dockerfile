# CakePHP 5 on ePHPm.
#
# Builds the official `cakephp/app` skeleton and adds a 2-file guestbook
# (migration + JSON controller) so the smoke test can exercise a database
# round trip through HTTP with CSRF protection on. For your own app replace
# the `create-project` line with `COPY . /app` + `composer install` and drop
# the demo/ lines.
#
# Build args:
#   EPHPM_TAG     ephpm/ephpm image tag (default v0.11.3-php8.5)
#   CAKE_VERSION  cakephp/app version constraint (default ^5.0)

ARG EPHPM_TAG=v0.11.3-php8.5
ARG CAKE_VERSION=^5.0

FROM docker.io/library/composer:2 AS vendor
ARG CAKE_VERSION
# --no-scripts: the skeleton's post-create-project script only copies
# app_local.example.php into place and sets a salt, done below instead.
RUN composer create-project --no-interaction --prefer-dist --no-dev --no-scripts \
        --ignore-platform-reqs cakephp/app /app "${CAKE_VERSION}"
WORKDIR /app
RUN cp config/app_local.example.php config/app_local.php
COPY demo/CreateGuestbook.php config/Migrations/20260101000000_CreateGuestbook.php
COPY demo/GuestbookController.php src/Controller/GuestbookController.php
COPY demo/GuestbookTable.php src/Model/Table/GuestbookTable.php

FROM docker.io/ephpm/ephpm:${EPHPM_TAG}
COPY --from=vendor /app /app
COPY ephpm.toml /etc/ephpm/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
WORKDIR /app
ENV DEBUG=false \
    APP_DEFAULT_TIMEZONE=UTC \
    DATABASE_URL=mysql://root:@127.0.0.1:3306/cake?encoding=utf8mb4 \
    EMAIL_TRANSPORT_DEFAULT_URL=
RUN chmod +x /usr/local/bin/entrypoint.sh && mkdir -p /var/lib/ephpm tmp logs

VOLUME ["/app/tmp", "/app/logs"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
