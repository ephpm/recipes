#!/bin/sh
# Container entrypoint: seed the data volume, then ePHPm in the foreground
# (or the feed updater). selfoss is configured from SELFOSS_* environment
# variables (its `env_prefix`), which override config.ini; the database
# schema is created by selfoss itself on first use.
#
#   entrypoint.sh                 -> ephpm serve --config $EPHPM_CONFIG
#   entrypoint.sh updater         -> cliupdate.php every SELFOSS_UPDATE_INTERVAL seconds
#   entrypoint.sh <command...>    -> run <command>
set -eu

cd /app
for d in cache favicons fulltextrss logs sqlite thumbnails; do
    [ -d "data/$d" ] || cp -a "/usr/local/share/selfoss-data/$d" data/
done

# SELFOSS_PASSWORD may be given in plain text (SELFOSS_PLAIN_PASSWORD): hash
# it the way selfoss's /password page does (password_hash).
if [ -n "${SELFOSS_PLAIN_PASSWORD:-}" ] && [ -z "${SELFOSS_PASSWORD:-}" ]; then
    SELFOSS_PASSWORD="$(php -r 'echo password_hash(getenv("SELFOSS_PLAIN_PASSWORD"), PASSWORD_DEFAULT);')"
    export SELFOSS_PASSWORD
fi
unset SELFOSS_PLAIN_PASSWORD

case "${1:-}" in
    updater)
        echo "==> refreshing feeds every ${SELFOSS_UPDATE_INTERVAL:-900} s"
        while :; do
            php cliupdate.php || echo "cliupdate.php exited with $?" >&2
            sleep "${SELFOSS_UPDATE_INTERVAL:-900}"
        done
        ;;
    ""|-*) exec ephpm serve --config "${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}" "$@" ;;
    *) exec "$@" ;;
esac
