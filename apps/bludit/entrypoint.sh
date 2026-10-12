#!/bin/sh
# Seed the bl-content volume, run Bludit's installer once (it is a web page:
# a single POST to install.php) on a private loopback port when
# BLUDIT_ADMIN_PASSWORD is set, then serve.
set -eu
APP=/var/www/html
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"
cd "$APP"
[ -e bl-content/pages ] || cp -a /usr/local/share/bludit/bl-content/. bl-content/

if [ ! -f bl-content/databases/site.php ] && [ -n "${BLUDIT_ADMIN_PASSWORD:-}" ]; then
    echo "==> installing Bludit"
    ephpm serve --config "$CONFIG" --listen 127.0.0.1:8099 >/tmp/install-server.log 2>&1 &
    srv=$!
    i=0
    until ephpm php -r 'exit(@file_get_contents("http://127.0.0.1:8099/install.php") === false ? 1 : 0);' 2>/dev/null; do
        i=$((i + 1)); [ "$i" -ge 30 ] && { echo "!!! installer server did not start" >&2; exit 1; }
        sleep 1
    done
    ephpm php -r '
        $form = http_build_query(["password" => getenv("BLUDIT_ADMIN_PASSWORD"), "timezone" => getenv("TZ") ?: "UTC",
            "language" => getenv("BLUDIT_LANGUAGE") ?: "en", "install" => ""]);
        file_get_contents("http://127.0.0.1:8099/install.php", false, stream_context_create(["http" => [
            "method" => "POST", "header" => "Content-Type: application/x-www-form-urlencoded", "content" => $form]]));
    ' >/dev/null
    kill "$srv" 2>/dev/null || true
    wait "$srv" 2>/dev/null || true
    [ -f bl-content/databases/site.php ] || { echo "!!! Bludit installer did not write bl-content/databases/site.php" >&2; exit 1; }
    echo "==> Bludit installed (user: admin)"
fi

case "${1:-}" in
    ""|-*) exec ephpm serve --config "$CONFIG" "$@" ;;
    *) exec "$@" ;;
esac
