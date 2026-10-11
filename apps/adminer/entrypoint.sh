#!/bin/sh
# Container entrypoint: the same ADMINER_DESIGN / ADMINER_PLUGINS handling as
# the official image, then ePHPm in the foreground.
set -eu
cd /var/www/html

# ADMINER_DESIGN=<name>: link designs/<name>/adminer.css as the stylesheet.
# Only on the first start, so a hand-placed adminer.css survives restarts.
if [ -n "${ADMINER_DESIGN:-}" ] && [ ! -e .adminer-init ]; then
    [ -f "designs/${ADMINER_DESIGN}/adminer.css" ] || { echo "!!! unknown ADMINER_DESIGN '${ADMINER_DESIGN}' (see designs/)" >&2; exit 1; }
    ln -sf "designs/${ADMINER_DESIGN}/adminer.css" adminer.css
fi

# ADMINER_PLUGINS="tables-filter dump-zip …": one stub per plugin.
number=1
for plugin in ${ADMINER_PLUGINS:-}; do
    ephpm php plugin-loader.php "$plugin" > "plugins-enabled/$(printf '%03d' "$number")-$plugin.php"
    number=$((number + 1))
done
touch .adminer-init

exec ephpm serve --config "${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}" "$@"
