#!/bin/sh
# Container entrypoint: seed the user/ volume, optionally create the first
# admin account, then ePHPm in the foreground.
#
#   entrypoint.sh                 -> ephpm serve --config $EPHPM_CONFIG
#   entrypoint.sh --listen ...    -> ephpm serve --config $EPHPM_CONFIG --listen ...
#   entrypoint.sh <command...>    -> run <command> after the same setup
set -eu

HTML=/var/www/html
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"
cd "$HTML"

# user/ (config, pages, accounts, plugins, themes) is a volume: seed it from
# the image when it is empty. Later image upgrades do not overwrite it —
# update plugins and themes with `bin/gpm` as usual.
if [ ! -e "$HTML/user/config/system.yaml" ]; then
    cp -a /usr/local/share/grav/user/. "$HTML/user/"
    echo "==> seeded user/ from the image"
fi
for d in cache logs images assets tmp backup user/data user/accounts; do mkdir -p "$HTML/$d"; done

# First admin account from the environment (optional — otherwise the admin
# panel at /admin asks for one on the first visit).
if [ -n "${GRAV_ADMIN_USER:-}" ] && [ -n "${GRAV_ADMIN_PASSWORD:-}" ] \
   && [ ! -e "$HTML/user/accounts/${GRAV_ADMIN_USER}.yaml" ]; then
    ephpm php bin/plugin login new-user --no-interaction \
        --user="$GRAV_ADMIN_USER" --password="$GRAV_ADMIN_PASSWORD" \
        --email="${GRAV_ADMIN_EMAIL:-admin@example.com}" --fullname="${GRAV_ADMIN_FULLNAME:-Administrator}" \
        --permissions=b --title="Site Administrator"
fi

case "${1:-}" in
    ""|-*) exec ephpm serve --config "$CONFIG" "$@" ;;
    *) exec "$@" ;;
esac
