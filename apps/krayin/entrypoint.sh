#!/bin/sh
# Container entrypoint: first-run installation (Krayin's own
# `artisan krayin-crm:install`, unattended), migrations on later starts,
# then ePHPm in the foreground.
#
#   entrypoint.sh                 -> ephpm serve --config $EPHPM_CONFIG
#   entrypoint.sh --listen ...    -> ephpm serve --config $EPHPM_CONFIG --listen ...
#   entrypoint.sh <command...>    -> run <command> once the server has installed
#                                    Krayin (the scheduler service,
#                                    `docker compose run --rm ephpm ephpm php artisan ...`)
set -eu

APP=/app
STORAGE=$APP/storage
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"

# storage/ is a volume. Seed it when it started out empty (a bind mount, or
# a pre-created one).
[ -d "$STORAGE/framework" ] || cp -a /usr/local/share/krayin/storage/. "$STORAGE/"
for d in app/public framework/cache/data framework/sessions framework/views logs; do
    mkdir -p "$STORAGE/$d"
done

# .env lives in the storage volume and /app/.env points at it: the installer
# writes APP_KEY into it, which must survive container recreation. Values
# set in the container environment win over the file for the running app.
case "${1:-}" in
    ""|-*) [ -f "$STORAGE/.env" ] || cp "$APP/.env.example" "$STORAGE/.env" ;;
    *)
        i=0
        until [ -f "$STORAGE/installed" ]; do
            i=$((i + 1)); [ "$i" -ge 600 ] && { echo "!!! Krayin was not installed by the server after 600s" >&2; exit 1; }
            sleep 1
        done
        ;;
esac
ln -sfn "$STORAGE/.env" "$APP/.env"

# set_env KEY VALUE — write KEY=VALUE into storage/.env. Unquoted on
# purpose: Krayin's installer reads the file itself (getEnvAtRuntime) and
# would keep the quotes as part of the value.
set_env() {
    esc="$(printf '%s' "$2" | sed 's/[\\|&]/\\&/g')"
    if grep -q "^$1=" "$STORAGE/.env"; then
        sed -i "s|^$1=.*|$1=$esc|" "$STORAGE/.env"
    else
        printf '%s=%s\n' "$1" "$2" >> "$STORAGE/.env"
    fi
}

# The installer configures itself from the .env *file*, not the process
# environment: copy the container's values into it (values must not contain
# spaces — the installer strips them).
if [ -w "$STORAGE/.env" ]; then
    for k in APP_URL APP_ENV APP_DEBUG APP_TIMEZONE APP_LOCALE APP_CURRENCY \
             DB_CONNECTION DB_HOST DB_PORT DB_DATABASE DB_USERNAME DB_PASSWORD DB_PREFIX; do
        eval "v=\${$k-__unset__}"
        [ "$v" = "__unset__" ] || set_env "$k" "$v"
    done
fi

echo "==> waiting for database at ${DB_HOST:-db}:${DB_PORT:-3306}"
i=0
until ephpm php -r '
    mysqli_report(MYSQLI_REPORT_OFF);
    $c = @mysqli_connect(getenv("DB_HOST") ?: "db", getenv("DB_USERNAME") ?: "root", getenv("DB_PASSWORD") ?: "", getenv("DB_DATABASE") ?: "krayin", (int) (getenv("DB_PORT") ?: 3306));
    exit($c ? 0 : 1);
' 2>/dev/null; do
    i=$((i + 1))
    [ "$i" -ge 60 ] && { echo "!!! database at ${DB_HOST:-db} not reachable after 60 tries" >&2; exit 1; }
    sleep 2
done

case "${1:-}" in
    ""|-*) ;;
    *) exec "$@" ;;
esac

# Does the database already hold a Krayin schema? (a recreated storage
# volume must never re-run the installer: it runs `migrate:fresh`)
has_schema() {
    ephpm php -r '
        mysqli_report(MYSQLI_REPORT_OFF);
        $c = mysqli_connect(getenv("DB_HOST") ?: "db", getenv("DB_USERNAME") ?: "root", getenv("DB_PASSWORD") ?: "", getenv("DB_DATABASE") ?: "krayin", (int) (getenv("DB_PORT") ?: 3306));
        $p = getenv("DB_PREFIX") ?: "";
        $r = $c ? mysqli_query($c, "SHOW TABLES LIKE \x27{$p}users\x27") : false;
        exit($r && mysqli_num_rows($r) > 0 ? 0 : 1);
    '
}

if [ ! -f "$STORAGE/installed" ]; then
    if has_schema; then
        echo "==> database already holds a Krayin schema; marking installed"
        echo "Krayin is successfully installed" > "$STORAGE/installed"
    else
        # Krayin's installer: APP_KEY, schema (migrate:fresh), seed data,
        # vendor:publish, storage:link and the admin user. Unattended
        # (--no-interaction takes every prompt's default, so the admin is
        # admin@example.com / admin123 until KRAYIN_ADMIN_* below replace it).
        # It runs with APP_ENV=local — in production Laravel refuses
        # migrate:fresh under --no-interaction, and the installer reads
        # APP_ENV from the .env file.
        echo "==> running artisan krayin-crm:install"
        set_env APP_ENV local
        APP_ENV=local ephpm php artisan krayin-crm:install --skip-env-check --no-interaction
        set_env APP_ENV "${APP_ENV:-production}"
        [ -f "$STORAGE/installed" ] || { echo "!!! krayin-crm:install did not complete (no storage/installed)" >&2; exit 1; }
        if [ -n "${KRAYIN_ADMIN_EMAIL:-}" ] && [ -n "${KRAYIN_ADMIN_PASSWORD:-}" ]; then
            echo "==> setting the admin account to $KRAYIN_ADMIN_EMAIL"
            ephpm php -r '
                $c = mysqli_connect(getenv("DB_HOST") ?: "db", getenv("DB_USERNAME") ?: "root", getenv("DB_PASSWORD") ?: "", getenv("DB_DATABASE") ?: "krayin", (int) (getenv("DB_PORT") ?: 3306));
                $p = getenv("DB_PREFIX") ?: "";
                $s = mysqli_prepare($c, "UPDATE {$p}users SET email = ?, password = ?, name = ? WHERE id = 1");
                $email = getenv("KRAYIN_ADMIN_EMAIL"); $hash = password_hash(getenv("KRAYIN_ADMIN_PASSWORD"), PASSWORD_BCRYPT); $name = getenv("KRAYIN_ADMIN_NAME") ?: "Admin";
                mysqli_stmt_bind_param($s, "sss", $email, $hash, $name);
                mysqli_stmt_execute($s);
            '
        fi
    fi
fi
echo "==> applying migrations"
ephpm php artisan migrate --force --no-interaction
echo "==> Krayin is ready"
exec ephpm serve --config "$CONFIG" "$@"
