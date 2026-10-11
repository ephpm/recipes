#!/bin/sh
# Container entrypoint: seed the volumes, install Flarum on the first start
# (or migrate after an image upgrade), then ePHPm in the foreground.
#
#   entrypoint.sh                 -> ephpm serve --config $EPHPM_CONFIG
#   entrypoint.sh --listen ...    -> ephpm serve --config $EPHPM_CONFIG --listen ...
#   entrypoint.sh <command...>    -> run <command> after the same setup
set -eu

APP=/app
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"
cd "$APP"

# storage/ and public/assets/ are volumes: seed what the image ships.
for d in cache formatter less locale logs sessions views; do mkdir -p "$APP/storage/$d"; done
[ -e "$APP/public/assets/avatars" ] || cp -a /usr/local/share/flarum/assets/. "$APP/public/assets/"

case "${DB_DRIVER:-mariadb}" in
    sqlite)
        # The single-container variant: SQLite in the data volume.
        DB_NAME="${DB_NAME:-/data/flarum.sqlite}"; export DB_NAME
        [ -f "$DB_NAME" ] || touch "$DB_NAME"
        ;;
    *)
        echo "==> waiting for database at ${DB_HOST:-db}:${DB_PORT:-3306}"
        i=0
        until ephpm php -r '
            mysqli_report(MYSQLI_REPORT_OFF);
            exit(@mysqli_connect(getenv("DB_HOST") ?: "db", getenv("DB_USER") ?: "flarum", getenv("DB_PASS") ?: "", getenv("DB_NAME") ?: "flarum", (int) (getenv("DB_PORT") ?: 3306)) ? 0 : 1);
        ' 2>/dev/null; do
            i=$((i + 1)); [ "$i" -ge 60 ] && { echo "!!! database not reachable after 60 tries" >&2; exit 1; }
            sleep 2
        done
        ;;
esac

if [ ! -s /data/config.php ]; then
    # The same variables as the mondedie/flarum image.
    : "${FORUM_URL:?FORUM_URL must be set (the public URL of the forum)}"
    : "${FLARUM_ADMIN_PASS:?FLARUM_ADMIN_PASS must be set for the first start}"
    ephpm php -r '
        echo json_encode([
            "debug" => false,
            "baseUrl" => rtrim(getenv("FORUM_URL"), "/"),
            "databaseConfiguration" => [
                "driver" => getenv("DB_DRIVER") ?: "mariadb",   // mariadb, mysql or sqlite
                "host" => getenv("DB_HOST") ?: "db",
                "port" => (int) (getenv("DB_PORT") ?: 3306),
                "database" => getenv("DB_NAME") ?: "flarum",
                "username" => getenv("DB_USER") ?: "flarum",
                "password" => getenv("DB_PASS") ?: "",
                "prefix" => getenv("DB_PREF") ?: "",
            ],
            "adminUser" => [
                "username" => getenv("FLARUM_ADMIN_USER") ?: "admin",
                "password" => getenv("FLARUM_ADMIN_PASS"),
                "email" => getenv("FLARUM_ADMIN_MAIL") ?: "admin@example.com",
            ],
            "settings" => ["forum_title" => getenv("FLARUM_TITLE") ?: "Flarum on ePHPm"],
        ]);
    ' > /tmp/flarum-install.json
    echo "==> installing Flarum"
    ephpm php flarum install --file=/tmp/flarum-install.json
    rm -f /tmp/flarum-install.json
else
    # After an image upgrade: pending migrations and a cache/asset rebuild.
    ephpm php flarum migrate
    ephpm php flarum cache:clear
fi

case "${1:-}" in
    ""|-*) exec ephpm serve --config "$CONFIG" "$@" ;;
    *) exec "$@" ;;
esac
