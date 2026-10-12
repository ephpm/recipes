#!/bin/sh
# Container entrypoint: seed the storage volume and .env, generate APP_KEY
# once, wait for the database, migrate (seeding on a fresh database), finish
# the installation wizard unattended when INVOICESHELF_ADMIN_PASSWORD is set,
# then ePHPm in the foreground.
#
#   entrypoint.sh                 -> ephpm serve --config $EPHPM_CONFIG
#   entrypoint.sh scheduler       -> Laravel's scheduler (schedule:work)
#   entrypoint.sh <command...>    -> run <command> after the same setup
set -eu

APP=/app
cd "$APP"

[ -n "$(ls -A storage 2>/dev/null)" ] || cp -a /usr/local/share/invoiceshelf/storage/. storage/
for d in app/public framework/cache/data framework/sessions framework/views logs; do mkdir -p "storage/$d"; done
ln -sfn ../storage/app/public public/storage        # `artisan storage:link`

# .env lives in the storage volume (APP_KEY must survive re-creation); the
# rest comes from the container environment, which wins over .env.
[ -f storage/.env ] || cp .env.example storage/.env
ln -sfn storage/.env .env
if grep -q '^APP_KEY=$' storage/.env && [ -z "${APP_KEY:-}" ]; then
    key="base64:$(php -r 'echo base64_encode(random_bytes(32));')"
    sed -i "s|^APP_KEY=.*|APP_KEY=$key|" storage/.env
    echo "==> generated APP_KEY into storage/.env"
fi

if [ "${1:-}" = "scheduler" ]; then
    until [ -f storage/.ephpm-ready ]; do sleep 5; done
    exec php artisan schedule:work
fi

if [ "${DB_CONNECTION:-sqlite}" != "sqlite" ]; then
    echo "==> waiting for database at ${DB_HOST:-db}:${DB_PORT:-3306}"
    i=0
    until php -r '
        try { new PDO(sprintf("%s:host=%s;port=%s;dbname=%s", getenv("DB_CONNECTION") === "pgsql" ? "pgsql" : "mysql",
              getenv("DB_HOST") ?: "db", getenv("DB_PORT") ?: "3306", getenv("DB_DATABASE") ?: "invoiceshelf"),
              getenv("DB_USERNAME") ?: "invoiceshelf", getenv("DB_PASSWORD") ?: ""); exit(0); } catch (Throwable $e) { exit(1); }
    ' 2>/dev/null; do
        i=$((i + 1))
        [ "$i" -ge 60 ] && { echo "!!! database not reachable after 60 tries" >&2; exit 1; }
        sleep 2
    done
fi

if php -r 'require "vendor/autoload.php"; $a = require "bootstrap/app.php"; $a->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap(); exit(App\Space\InstallUtils::isDbCreated() ? 0 : 1);' 2>/dev/null; then
    echo "==> running database migrations"
    php artisan migrate --force --no-interaction
else
    # the wizard's database step: migrate --seed (currencies, countries, the
    # placeholder admin and company)
    echo "==> creating the schema (migrate --seed)"
    php artisan migrate --seed --force --no-interaction
    if [ -n "${INVOICESHELF_ADMIN_PASSWORD:-}" ]; then
        php /usr/local/share/invoiceshelf/setup.php
    else
        echo "==> finish the installation wizard in the browser"
    fi
fi
touch storage/.ephpm-ready

case "${1:-}" in
    ""|-*) exec ephpm serve --config "${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}" "$@" ;;
    *) exec "$@" ;;
esac
