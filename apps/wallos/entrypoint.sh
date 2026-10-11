#!/bin/sh
# Container entrypoint: first-run setup (database creation + migrations,
# the same scripts the official startup.sh runs), then ePHPm in the
# foreground.
#
#   entrypoint.sh                 -> ephpm serve --config $EPHPM_CONFIG
#   entrypoint.sh --listen ...    -> ephpm serve --config $EPHPM_CONFIG --listen ...
#   entrypoint.sh <command...>    -> run <command> after the same setup
#                                    (the cron service runs `cron -f`)
set -eu

HTML=/var/www/html
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"
cd "$HTML"

# db/ and images/uploads/logos are volumes. Seed what the image ships when
# a volume started out empty (a bind mount, or a pre-created one).
[ -e "$HTML/db/wallos.empty.db" ] || cp -an /usr/local/share/wallos/db/. "$HTML/db/"
[ -d "$HTML/images/uploads/logos/avatars" ] || cp -an /usr/local/share/wallos/logos/. "$HTML/images/uploads/logos/"

# Create the database from the empty template on first start, then apply
# migrations — exactly what the official startup script does.
ephpm php endpoints/cronjobs/createdatabase.php
ephpm php endpoints/db/migrate.php

case "${1:-}" in
    ""|-*)
        # The official startup also refreshes payment dates and exchange
        # rates and checks for updates once; do it in the background (the
        # last two need internet access and must not delay serving).
        (
            ephpm php endpoints/cronjobs/updatenextpayment.php || true
            ephpm php endpoints/cronjobs/updateexchange.php || true
            ephpm php endpoints/cronjobs/checkforupdates.php || true
        ) >/dev/null 2>&1 &
        exec ephpm serve --config "$CONFIG" "$@"
        ;;
    *) exec "$@" ;;
esac
