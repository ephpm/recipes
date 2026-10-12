#!/bin/sh
# Container entrypoint — the official fusio/fusio image's docker-entrypoint.sh
# on the embedded PHP: wait for the DB, migrate, first backend user, write the
# API URL into the apps, deploy .fusio.yml, then ePHPm in the foreground.
#
#   entrypoint.sh                 -> setup, then ephpm serve --config $EPHPM_CONFIG
#   entrypoint.sh --listen ...    -> same, extra args to `ephpm serve`
#   entrypoint.sh <command...>    -> wait for the DB, then run <command> (the cron sidecar)
set -eu
cd /app
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"
fusio() { ephpm php bin/fusio "$@"; }

: "${FUSIO_PROJECT_KEY:?set FUSIO_PROJECT_KEY (32 random hex chars; it encrypts stored connection credentials)}"
: "${FUSIO_CONNECTION:?set FUSIO_CONNECTION, e.g. pdo-mysql://fusio:secret@db/fusio}"

echo "==> waiting for the database"
fusio system:wait_for

case "${1:-}" in ""|-*) ;; *) exec "$@" ;; esac

if ! fusio migration:up-to-date; then
    fusio migration:migrate --no-interaction
fi

if ! fusio system:check user; then
    fusio adduser --role=1 --username="${FUSIO_BACKEND_USER:?}" --email="${FUSIO_BACKEND_EMAIL:?}" --password="${FUSIO_BACKEND_PW:?}"
fi

# writes FUSIO_URL / FUSIO_APPS_URL into the installed apps' config
fusio marketplace:env -

# deploy the resources described in .fusio.yml (none by default)
fusio login --username="$FUSIO_BACKEND_USER" --password="$FUSIO_BACKEND_PW"
fusio deploy
fusio logout

exec ephpm serve --config "$CONFIG" "$@"
