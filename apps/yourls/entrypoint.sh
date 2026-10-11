#!/bin/sh
# Container entrypoint: seed the user/ volume, generate the cookie key once,
# wait for an external database, then ePHPm in the foreground.
set -eu

HTML=/var/www/html
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"

# user/ (plugins, pages, languages, config.php) lives in a volume; make sure
# the bits the image ships are there even when the volume was created empty.
for d in config.php plugins pages languages; do
    [ -e "$HTML/user/$d" ] || cp -a "/usr/local/share/yourls/user/$d" "$HTML/user/"
done

# Cookie encryption key: generated once and kept in the volume unless
# YOURLS_COOKIEKEY is given (the official image patches a random one into
# config.php the same way).
if [ -z "${YOURLS_COOKIEKEY:-}" ] && [ ! -s "$HTML/user/cookiekey.txt" ]; then
    ephpm php -r 'echo bin2hex(random_bytes(32));' > "$HTML/user/cookiekey.txt"
fi

# Wait for an external database (the embedded one starts with the server).
DB_HOST="${YOURLS_DB_HOST:-127.0.0.1:3306}"
case "$DB_HOST" in
    127.0.0.1*|localhost*) ;;
    *)
        echo "==> waiting for database at $DB_HOST"
        i=0
        until ephpm php -r '
            [$h, $p] = array_pad(explode(":", $argv[1], 2), 2, 3306);
            mysqli_report(MYSQLI_REPORT_OFF);
            $c = @mysqli_connect($h, getenv("YOURLS_DB_USER") ?: "root", getenv("YOURLS_DB_PASS") ?: "", getenv("YOURLS_DB_NAME") ?: "yourls", (int) $p);
            exit($c ? 0 : 1);
        ' -- "$DB_HOST" 2>/dev/null; do
            i=$((i + 1))
            [ "$i" -ge 60 ] && { echo "!!! database at $DB_HOST not reachable after 60 tries" >&2; exit 1; }
            sleep 2
        done
        ;;
esac

exec ephpm serve --config "$CONFIG" "$@"
