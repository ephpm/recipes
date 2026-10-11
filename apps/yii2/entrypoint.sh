#!/bin/sh
# First-run setup (cookie validation key, `yii migrate` once the database
# answers), then ePHPm in the foreground.
#
#   entrypoint.sh                 -> ephpm serve --config $EPHPM_CONFIG
#   entrypoint.sh --listen ...    -> ephpm serve --config $EPHPM_CONFIG --listen ...
set -eu
cd /app
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"
mkdir -p runtime web/assets

# cookieValidationKey: COOKIE_VALIDATION_KEY, else one generated once into
# the runtime volume (the template's composer script writes a random one
# into config/web.php instead).
if [ -z "${COOKIE_VALIDATION_KEY:-}" ]; then
    [ -s runtime/.cookie_validation_key ] || ephpm php -r 'echo bin2hex(random_bytes(32));' > runtime/.cookie_validation_key
    COOKIE_VALIDATION_KEY="$(cat runtime/.cookie_validation_key)"
    export COOKIE_VALIDATION_KEY
fi

# Wait for the database (migrate/history fails until it answers), then
# apply the application's migrations. SKIP_MIGRATE=1 to skip.
if [ "${SKIP_MIGRATE:-0}" != "1" ]; then
    i=0
    until ephpm php yii migrate/history --interactive=0 >/dev/null 2>&1; do
        i=$((i + 1))
        [ "$i" -ge 60 ] && { echo "!!! database not reachable after 60 tries" >&2; exit 1; }
        sleep 2
    done
    echo "==> running migrations"
    ephpm php yii migrate --interactive=0
fi

exec ephpm serve --config "$CONFIG" "$@"
