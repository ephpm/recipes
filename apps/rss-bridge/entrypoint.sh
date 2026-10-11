#!/bin/sh
# Container entrypoint: install custom files from /config the way the
# official image's docker-entrypoint.sh does (*Bridge.php, *Format.php,
# config.ini.php, whitelist.txt, DEBUG), then ePHPm in the foreground.
#
#   entrypoint.sh                 -> ephpm serve --config $EPHPM_CONFIG
#   entrypoint.sh --listen ...    -> ephpm serve --config $EPHPM_CONFIG --listen ...
#   entrypoint.sh <command...>    -> run <command> after the same setup
set -eu

APP=/app
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"

for file in /config/*; do
    [ -f "$file" ] || continue
    name="$(basename "$file")"
    case "$name" in
        *" "*) echo "Custom file $name has a space in the name and will be skipped." ;;
        *Bridge.php) cp "$file" "$APP/bridges/"; echo "Custom Bridge $name added." ;;
        *Format.php) cp "$file" "$APP/formats/"; echo "Custom Format $name added." ;;
        config.ini.php) cp "$file" "$APP/"; echo "Custom config.ini.php added." ;;
        whitelist.txt) cp "$file" "$APP/"; echo "Custom whitelist.txt added." ;;
        DEBUG) cp "$file" "$APP/"; echo "DEBUG file added." ;;
    esac
done
mkdir -p "$APP/cache"

case "${1:-}" in
    ""|-*) exec ephpm serve --config "$CONFIG" "$@" ;;
    *) exec "$@" ;;
esac
