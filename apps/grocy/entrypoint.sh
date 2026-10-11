#!/bin/sh
# Container entrypoint: seed the data volume (config.php from config-dist.php,
# as the linuxserver image does), then ePHPm in the foreground. Grocy creates
# and migrates its SQLite database itself on the first request.
#
#   entrypoint.sh                 -> ephpm serve --config $EPHPM_CONFIG
#   entrypoint.sh --listen ...    -> ephpm serve --config $EPHPM_CONFIG --listen ...
#   entrypoint.sh <command...>    -> run <command> after the same setup
set -eu

HTML=/var/www/html
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"

[ -e "$HTML/data/plugins" ] || cp -a /usr/local/share/grocy/data/. "$HTML/data/"
[ -f "$HTML/data/config.php" ] || cp "$HTML/config-dist.php" "$HTML/data/config.php"
mkdir -p "$HTML/data/viewcache" "$HTML/data/storage"

case "${1:-}" in
    ""|-*) exec ephpm serve --config "$CONFIG" "$@" ;;
    *) exec "$@" ;;
esac
