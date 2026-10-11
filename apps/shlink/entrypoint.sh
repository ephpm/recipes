#!/bin/sh
# Container entrypoint: the official image's docker-entrypoint.sh, minus
# RoadRunner — create the data directories, run `shlink-installer init`
# (schema, migrations, ORM proxies, optional initial API key), then run
# ePHPm in the foreground.
set -eu

cd /etc/shlink
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"

# data/ lives in a volume; seed it when it was created empty.
if [ -z "$(ls -A data 2>/dev/null)" ]; then
    cp -a /usr/local/share/shlink-data/. data/
fi
mkdir -p data/cache data/locks data/log data/proxies data/temp-geolite

# Read env vars through Shlink's own command so the `*_FILE` fallback applies.
geolite_license_key="$(shlink env-var:read GEOLITE_LICENSE_KEY)"
skip_initial_geolite_download="$(shlink env-var:read SKIP_INITIAL_GEOLITE_DOWNLOAD)"
initial_api_key="$(shlink env-var:read INITIAL_API_KEY)"
db_driver="$(shlink env-var:read DB_DRIVER)"
db_host="$(shlink env-var:read DB_HOST)"

# The official entrypoint runs `shlink-installer init`, and Shlink's own
# `db:create` / `db:migrate` wrap the Doctrine tools — all of them spawn a
# sub-process through PHP_BINARY (Symfony's PhpExecutableFinder). Under
# `ephpm php` PHP_BINARY is the ephpm executable, not a PHP CLI, so those
# sub-processes fail (see issues/shlink.md). Run the same Doctrine steps the
# commands would run (module/CLI/src/Command/Db/*.php) on the embedded PHP
# directly instead.
tables_exist() {
    ephpm php -r '
        $driver = getenv("DB_DRIVER") ?: "sqlite";
        $dsn = match ($driver) {
            "sqlite" => "sqlite:data/database.sqlite",
            "postgres" => sprintf("pgsql:host=%s;port=%s;dbname=%s", getenv("DB_HOST"), getenv("DB_PORT") ?: 5432, getenv("DB_NAME")),
            default => sprintf("mysql:host=%s;port=%s;dbname=%s", getenv("DB_HOST"), getenv("DB_PORT") ?: 3306, getenv("DB_NAME")),
        };
        try {
            $pdo = new PDO($dsn, getenv("DB_USER") ?: null, getenv("DB_PASSWORD") ?: null);
            $pdo->query("SELECT 1 FROM short_urls LIMIT 1");
            exit(0);
        } catch (Throwable) {
            exit(1);
        }
    ' 2>/dev/null
}

init() {
    if tables_exist; then
        echo "==> database already exists, migrating"
    else
        echo "==> creating database tables"
        ephpm php bin/doctrine orm:schema-tool:create --no-interaction
    fi
    ephpm php vendor/doctrine/migrations/bin/doctrine-migrations.php migrations:migrate --no-interaction
    ephpm php bin/doctrine orm:generate-proxies --no-interaction
    ephpm php bin/doctrine orm:clear-cache:metadata --no-interaction
    if [ -n "$geolite_license_key" ] && [ "$skip_initial_geolite_download" != "true" ]; then
        shlink visit:download-db --no-interaction || echo "!!! GeoLite2 download failed; Shlink retries when it first needs it" >&2
    fi
    if [ -n "$initial_api_key" ]; then
        shlink api-key:initial "$initial_api_key" --no-interaction
    fi
    echo "==> Shlink is ready"
}

case "$db_driver:$db_host" in
    sqlite:*|:*)
        init
        ;;
    *:127.0.0.1|*:localhost)
        # The embedded database only exists while `ephpm serve` runs, so
        # initialise in the background once its listener answers.
        (
            i=0
            until ephpm php -r 'exit(@fsockopen("127.0.0.1", (int) ($argv[1] ?: 3306), $e, $s, 1) ? 0 : 1);' \
                    "$(shlink env-var:read DB_PORT)" 2>/dev/null; do
                i=$((i + 1))
                [ "$i" -ge 60 ] && { echo "!!! embedded database listener not up after 60 tries" >&2; exit 1; }
                sleep 1
            done
            init
        ) &
        ;;
    *)
        echo "==> waiting for database at $db_host"
        i=0
        until ephpm php -r 'exit(@fsockopen($argv[1], (int) ($argv[2] ?: 3306), $e, $s, 2) ? 0 : 1);' \
                "$db_host" "$(shlink env-var:read DB_PORT)" 2>/dev/null; do
            i=$((i + 1))
            [ "$i" -ge 60 ] && { echo "!!! database at $db_host not reachable after 60 tries" >&2; exit 1; }
            sleep 2
        done
        init
        ;;
esac

exec ephpm serve --config "$CONFIG" "$@"
