# CodeIgniter 4 on ePHPm.
#
# Builds the official `codeigniter4/appstarter` skeleton (CI4 4.7) and adds a
# tiny guestbook (one migration, one controller, two routes) so the smoke test
# can exercise a database round trip through HTTP. For your own application
# replace the `create-project` line with `COPY . /app` + `composer install`
# and drop the demo/ files.
#
# Build args:
#   EPHPM_TAG    ephpm/ephpm image tag (default v0.11.3-php8.5)
#   CI4_VERSION  codeigniter4/appstarter version constraint (default ^4.7)

ARG EPHPM_TAG=v0.11.3-php8.5
ARG CI4_VERSION=^4.7

FROM docker.io/library/composer:2 AS vendor
ARG CI4_VERSION
RUN composer create-project --no-interaction --prefer-dist --no-dev --no-scripts \
        --ignore-platform-reqs codeigniter4/appstarter /app "${CI4_VERSION}"
WORKDIR /app
# The recipe's guestbook demo (migration + controller + routes).
COPY demo/CreateGuestbook.php app/Database/Migrations/2026-01-01-000000_CreateGuestbook.php
COPY demo/Guestbook.php app/Controllers/Guestbook.php
RUN printf '\n// recipe demo\n$routes->get("guestbook", "Guestbook::index");\n$routes->post("guestbook", "Guestbook::create");\n' >> app/Config/Routes.php \
    && rm -f .env

FROM docker.io/ephpm/ephpm:${EPHPM_TAG}
COPY --from=vendor /app /app
COPY ephpm.toml ephpm.embedded.toml /etc/ephpm/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
WORKDIR /app
ENV CI_ENVIRONMENT=production \
    app_baseURL=http://localhost:8080/ \
    database_default_DBDriver=MySQLi \
    database_default_hostname=127.0.0.1 \
    database_default_port=3306 \
    database_default_database=ci4 \
    database_default_username=root \
    database_default_password=
RUN chmod +x /usr/local/bin/entrypoint.sh && mkdir -p /var/lib/ephpm writable/cache writable/logs writable/session writable/uploads

VOLUME ["/app/writable"]
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
