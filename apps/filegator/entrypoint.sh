#!/bin/sh
# Container entrypoint: seed the private volume, generate the CSRF key and
# (optionally) set the admin password on first start, then ePHPm in the
# foreground.
#
#   entrypoint.sh                 -> ephpm serve --config $EPHPM_CONFIG
#   entrypoint.sh --listen ...    -> ephpm serve --config $EPHPM_CONFIG --listen ...
#   entrypoint.sh <command...>    -> run <command> after the same setup
set -eu

FG=/var/www/filegator
PRIV=$FG/private
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"

# private/ (users.json, sessions, logs, tmp) is a volume.
[ -e "$PRIV/users.json.blank" ] || cp -a /usr/local/share/filegator-private/. "$PRIV/"
mkdir -p "$PRIV/logs" "$PRIV/sessions" "$PRIV/tmp"

# The sample configuration ships a fixed csrf_key ("123456"); generate one
# per installation unless FILEGATOR_CSRF_KEY is given.
if [ -z "${FILEGATOR_CSRF_KEY:-}" ] && [ ! -s "$PRIV/csrf_key" ]; then
    ephpm php -r 'echo bin2hex(random_bytes(32));' > "$PRIV/csrf_key"
    chmod 600 "$PRIV/csrf_key"
fi

# First start: users.json from the blank template (admin / admin123, as
# upstream), with FILEGATOR_ADMIN_PASSWORD applied when set.
if [ ! -f "$PRIV/users.json" ]; then
    cp "$PRIV/users.json.blank" "$PRIV/users.json"
    if [ -n "${FILEGATOR_ADMIN_PASSWORD:-}" ]; then
        ephpm php -r '
            $f = $argv[1];
            $u = json_decode(file_get_contents($f), true);
            foreach ($u as &$user) {
                if ($user["username"] === "admin") {
                    $user["password"] = password_hash(getenv("FILEGATOR_ADMIN_PASSWORD"), PASSWORD_BCRYPT);
                }
            }
            file_put_contents($f, json_encode($u));
        ' "$PRIV/users.json"
        echo "==> admin password set from FILEGATOR_ADMIN_PASSWORD"
    else
        echo "==> users.json created: log in as admin / admin123 and change the password" >&2
    fi
fi

case "${1:-}" in
    ""|-*) exec ephpm serve --config "$CONFIG" "$@" ;;
    *) exec "$@" ;;
esac
