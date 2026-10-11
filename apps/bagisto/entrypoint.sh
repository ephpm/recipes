#!/bin/sh
# Container entrypoint: first-run installation (Bagisto's own
# `artisan bagisto:install --no-interaction`), migrations on later starts,
# then ePHPm in the foreground.
#
#   entrypoint.sh                 -> ephpm serve --config $EPHPM_CONFIG
#   entrypoint.sh --listen ...    -> ephpm serve --config $EPHPM_CONFIG --listen ...
#   entrypoint.sh <command...>    -> run <command> once the server has installed
#                                    Bagisto (the scheduler service,
#                                    `docker compose run --rm ephpm ephpm php artisan ...`)
set -eu

APP=/app
STORAGE=$APP/storage
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"

# storage/ is a volume. Seed it when it started out empty (a bind mount, or
# a pre-created one).
[ -d "$STORAGE/framework" ] || cp -a /usr/local/share/bagisto/storage/. "$STORAGE/"
for d in app/public framework/cache/data framework/sessions framework/views logs; do
    mkdir -p "$STORAGE/$d"
done

# .env lives in the storage volume and /app/.env points at it: the installer
# writes APP_KEY into it, which must survive container recreation. Values
# set in the container environment win over the file.
case "${1:-}" in
    ""|-*) [ -f "$STORAGE/.env" ] || cp "$APP/.env.example" "$STORAGE/.env" ;;
    *)
        i=0
        until [ -f "$STORAGE/installed" ]; do
            i=$((i + 1)); [ "$i" -ge 600 ] && { echo "!!! Bagisto was not installed by the server after 600s" >&2; exit 1; }
            sleep 1
        done
        ;;
esac
ln -sfn "$STORAGE/.env" "$APP/.env"

# Bagisto's installer reloads its settings from the .env *file* (not the
# process environment), so copy the container's values into it.
if [ -w "$STORAGE/.env" ]; then
    for k in APP_NAME APP_URL APP_ENV APP_DEBUG APP_TIMEZONE APP_LOCALE APP_CURRENCY APP_ADMIN_URL \
             DB_CONNECTION DB_HOST DB_PORT DB_DATABASE DB_USERNAME DB_PASSWORD DB_PREFIX; do
        eval "v=\${$k-__unset__}"
        [ "$v" = "__unset__" ] && continue
        esc="$(printf '%s' "$v" | sed 's/[\\|&]/\\&/g')"
        if grep -q "^$k=" "$STORAGE/.env"; then
            sed -i "s|^$k=.*|$k=\"$esc\"|" "$STORAGE/.env"
        else
            printf '%s="%s"\n' "$k" "$v" >> "$STORAGE/.env"
        fi
    done
fi

echo "==> waiting for database at ${DB_HOST:-db}:${DB_PORT:-3306}"
i=0
until ephpm php -r '
    mysqli_report(MYSQLI_REPORT_OFF);
    $c = @mysqli_connect(getenv("DB_HOST") ?: "db", getenv("DB_USERNAME") ?: "root", getenv("DB_PASSWORD") ?: "", getenv("DB_DATABASE") ?: "bagisto", (int) (getenv("DB_PORT") ?: 3306));
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

# Does the database already hold a Bagisto schema? (a recreated storage
# volume must never re-run the installer: it starts with `db:wipe`)
has_schema() {
    ephpm php -r '
        mysqli_report(MYSQLI_REPORT_OFF);
        $c = mysqli_connect(getenv("DB_HOST") ?: "db", getenv("DB_USERNAME") ?: "root", getenv("DB_PASSWORD") ?: "", getenv("DB_DATABASE") ?: "bagisto", (int) (getenv("DB_PORT") ?: 3306));
        $p = getenv("DB_PREFIX") ?: "";
        $r = $c ? mysqli_query($c, "SHOW TABLES LIKE \x27{$p}admins\x27") : false;
        exit($r && mysqli_num_rows($r) > 0 ? 0 : 1);
    '
}

if [ ! -f "$STORAGE/installed" ]; then
    if has_schema; then
        echo "==> database already holds a Bagisto schema; marking installed"
        echo "Bagisto is successfully installed." > "$STORAGE/installed"
    else
        # Bagisto's unattended installer: APP_KEY, schema, seed data (locale,
        # currency, channel, the default admin admin@example.com / admin123),
        # storage:link, then storage/installed.
        echo "==> running artisan bagisto:install"
        # It runs with APP_ENV=local (process and .env file, which the
        # installer reloads): in production Laravel refuses the installer's
        # db:wipe / migrate:fresh under --no-interaction.
        sed -i "s|^APP_ENV=.*|APP_ENV=local|" "$STORAGE/.env"
        APP_ENV=local ephpm php artisan bagisto:install --no-interaction
        sed -i "s|^APP_ENV=.*|APP_ENV=\"${APP_ENV:-production}\"|" "$STORAGE/.env"
        [ -f "$STORAGE/installed" ] || { echo "!!! bagisto:install did not complete (no storage/installed)" >&2; exit 1; }
        if [ -n "${BAGISTO_ADMIN_EMAIL:-}" ] && [ -n "${BAGISTO_ADMIN_PASSWORD:-}" ]; then
            echo "==> setting the admin account to $BAGISTO_ADMIN_EMAIL"
            ephpm php -r '
                $c = mysqli_connect(getenv("DB_HOST") ?: "db", getenv("DB_USERNAME") ?: "root", getenv("DB_PASSWORD") ?: "", getenv("DB_DATABASE") ?: "bagisto", (int) (getenv("DB_PORT") ?: 3306));
                $p = getenv("DB_PREFIX") ?: "";
                $s = mysqli_prepare($c, "UPDATE {$p}admins SET email = ?, password = ? WHERE id = 1");
                $email = getenv("BAGISTO_ADMIN_EMAIL"); $hash = password_hash(getenv("BAGISTO_ADMIN_PASSWORD"), PASSWORD_BCRYPT);
                mysqli_stmt_bind_param($s, "ss", $email, $hash);
                mysqli_stmt_execute($s);
                exit(mysqli_stmt_affected_rows($s) === 1 ? 0 : 1);
            '
        fi
    fi
fi
echo "==> applying migrations"
ephpm php artisan migrate --force --no-interaction
echo "==> Bagisto is ready"
exec ephpm serve --config "$CONFIG" "$@"
