#!/bin/sh
# Container entrypoint: the official docker-entrypoint.sh's install/migrate
# actions on the embedded PHP, then ePHPm in the foreground. With arguments
# (the `cron` service) it waits for the install and runs them instead.
set -eu

cd /var/www/html
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"

# data/, custom/ and client/custom live in volumes; seed them when created empty.
[ -n "$(ls -A data 2>/dev/null)" ] || cp -a /usr/local/share/espocrm/data/. data/
[ -n "$(ls -A custom 2>/dev/null)" ] || cp -a /usr/local/share/espocrm/custom/. custom/
[ -n "$(ls -A client/custom 2>/dev/null)" ] || cp -a /usr/local/share/espocrm/client-custom/. client/custom/
mkdir -p data/cache data/logs data/upload

# The same defaults as the official image.
ESPOCRM_DATABASE_PLATFORM="${ESPOCRM_DATABASE_PLATFORM:-Mysql}"
ESPOCRM_DATABASE_HOST="${ESPOCRM_DATABASE_HOST:-mysql}"
ESPOCRM_DATABASE_PORT="${ESPOCRM_DATABASE_PORT:-}"
ESPOCRM_DATABASE_NAME="${ESPOCRM_DATABASE_NAME:-espocrm}"
ESPOCRM_DATABASE_USER="${ESPOCRM_DATABASE_USER:-root}"
ESPOCRM_DATABASE_PASSWORD="${ESPOCRM_DATABASE_PASSWORD:-password}"
ESPOCRM_ADMIN_USERNAME="${ESPOCRM_ADMIN_USERNAME:-admin}"
ESPOCRM_ADMIN_PASSWORD="${ESPOCRM_ADMIN_PASSWORD:-password}"
ESPOCRM_LANGUAGE="${ESPOCRM_LANGUAGE:-en_US}"
ESPOCRM_SITE_URL="${ESPOCRM_SITE_URL:-http://localhost:8080}"

wait_db() {
    local port="${ESPOCRM_DATABASE_PORT:-3306}"
    case "$ESPOCRM_DATABASE_PLATFORM" in Postgresql) port="${ESPOCRM_DATABASE_PORT:-5432}" ;; esac
    echo "==> waiting for database at $ESPOCRM_DATABASE_HOST:$port"
    i=0
    until ephpm php -r 'exit(@fsockopen($argv[1], (int) $argv[2], $e, $s, 2) ? 0 : 1);' "$ESPOCRM_DATABASE_HOST" "$port" 2>/dev/null; do
        i=$((i + 1))
        [ "$i" -ge 90 ] && { echo "!!! database at $ESPOCRM_DATABASE_HOST:$port not reachable after 90 tries" >&2; exit 1; }
        sleep 2
    done
}

# ESPOCRM_CONFIG_<KEY>=value → config key (official image behaviour, flat keys only here)
apply_config_env() {
    env | while IFS='=' read -r name value; do
        case "$name" in
            ESPOCRM_CONFIG_*)
                key="$(printf '%s' "${name#ESPOCRM_CONFIG_}" | tr '[:upper:]' '[:lower:]' | sed 's/__/./g; s/_\([a-z]\)/\U\1/g')"
                espocrm config:set "$key" "$value"
                ;;
        esac
    done
}

install() {
    echo "==> installing EspoCRM"
    rm -rf data/cache
    espocrm config:populate
    espocrm config:set database.platform "$ESPOCRM_DATABASE_PLATFORM"
    espocrm config:set database.host "$ESPOCRM_DATABASE_HOST"
    espocrm config:set database.port "$ESPOCRM_DATABASE_PORT"
    espocrm config:set database.dbname "$ESPOCRM_DATABASE_NAME"
    espocrm config:set database.user "$ESPOCRM_DATABASE_USER"
    espocrm config:set database.password "$ESPOCRM_DATABASE_PASSWORD"
    i=0
    until [ "$(espocrm db:check 2>/dev/null)" = "OK" ]; do
        i=$((i + 1))
        [ "$i" -ge 20 ] && { echo "!!! database connection failed (db:check)" >&2; exit 1; }
        sleep 3
    done
    espocrm rebuild >/dev/null
    espocrm create-admin-user "$ESPOCRM_ADMIN_USERNAME" >/dev/null 2>&1 || true
    printf '%s\n' "$ESPOCRM_ADMIN_PASSWORD" | espocrm set-password "$ESPOCRM_ADMIN_USERNAME" >/dev/null
    espocrm config:set language "$ESPOCRM_LANGUAGE"
    espocrm config:set siteUrl "$ESPOCRM_SITE_URL"
    [ -n "${ESPOCRM_DATE_FORMAT:-}" ] && espocrm config:set dateFormat "$ESPOCRM_DATE_FORMAT"
    [ -n "${ESPOCRM_TIME_FORMAT:-}" ] && espocrm config:set timeFormat "$ESPOCRM_TIME_FORMAT"
    [ -n "${ESPOCRM_TIME_ZONE:-}" ] && espocrm config:set timeZone "$ESPOCRM_TIME_ZONE"
    [ -n "${ESPOCRM_WEEK_START:-}" ] && espocrm config:set weekStart "$ESPOCRM_WEEK_START" --type=int
    [ -n "${ESPOCRM_DEFAULT_CURRENCY:-}" ] && espocrm config:set defaultCurrency "$ESPOCRM_DEFAULT_CURRENCY"
    espocrm populate-scheduled-jobs
    # The official image enables parallel job processing (pcntl forks inside
    # its daemon). Jobs run from a plain `cron.php` loop here, so leave it off.
    espocrm config:set jobRunInParallel false --type=bool
    espocrm app-check
    espocrm config:set isInstalled true --type=bool
    echo "==> installation completed"
}

migrate() {
    espocrm clear-cache
    espocrm migrate
}

wait_db
if [ "$#" -gt 0 ]; then
    # cron service: wait until the web container has installed, then run
    until [ "$(espocrm config:get isInstalled 2>/dev/null)" = "true" ]; do sleep 5; done
    exec "$@"
fi

if [ "$(espocrm config:get isInstalled 2>/dev/null)" = "true" ]; then
    migrate
else
    install
fi
apply_config_env
echo "==> EspoCRM is ready"

exec ephpm serve --config "$CONFIG"
