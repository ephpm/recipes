#!/bin/sh
# Container entrypoint: seed the data/conf/plugins/tpl volumes from the
# image when they were mounted empty, then ePHPm in the foreground.
set -eu

HTML=/var/www/html
SEED=/usr/local/share/dokuwiki

seed() { # seed <volume dir> <pristine dir>
    if [ -z "$(ls -A "$1" 2>/dev/null)" ]; then
        mkdir -p "$1" && cp -a "$2/." "$1/"
    fi
}
seed "$HTML/data" "$SEED/data"
seed "$HTML/conf" "$SEED/conf"
seed "$HTML/lib/plugins" "$SEED/plugins"
seed "$HTML/lib/tpl" "$SEED/tpl"
# the directories DokuWiki writes to must exist even if an old volume lacks one
for d in attic cache index locks media media_attic media_meta meta pages tmp log; do
    mkdir -p "$HTML/data/$d"
done

exec ephpm serve --config "${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}" "$@"
