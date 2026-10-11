#!/bin/sh
# Container entrypoint: first-run setup (the same FRESHRSS_INSTALL /
# FRESHRSS_USER / CRON_MIN / TZ variables as the official image), then ePHPm
# in the foreground.
set -eu

APP=/var/www/FreshRSS
CONFIG="${EPHPM_CONFIG:-/etc/ephpm/ephpm.toml}"
cd "$APP"

# php.ini directives that come from the environment (read via [php] ini_file).
mkdir -p /run/ephpm
printf 'date.timezone = "%s"\n' "${TZ:-UTC}" > /run/ephpm/php.ini

# Make sure the data/ volume has every directory FreshRSS needs.
# (`php` is /usr/local/bin/php, the embedded-PHP shim — see the `php` file.)
php ./cli/prepare.php >/dev/null

# One-time install + default user, driven by the same variables (and CLI
# arguments) as freshrss/freshrss. Shell-parsed, so quoting works.
# do-install.php / create-user.php exit 3 when the step was already done.
first_run_setup() {
    if [ -n "${FRESHRSS_INSTALL:-}" ]; then
        eval "set -- $(printf '%s' "$FRESHRSS_INSTALL" | tr '\r\n' '  ')"
        i=0
        while :; do
            # `-f script -- args` (as in the official entrypoint): with -f the
            # `--` is consumed; without it php-cli (and ephpm php) pass it on.
            set +e; php -f ./cli/do-install.php -- "$@"; rc=$?; set -e
            case "$rc" in
                0) echo "==> FreshRSS installed"; break ;;
                3) echo "==> FreshRSS already installed; no change performed"; break ;;
            esac
            i=$((i + 1))
            [ "$i" -ge 30 ] && { echo "!!! FreshRSS installation failed (exit $rc)" >&2; exit "$rc"; }
            echo "==> installation attempt $i failed (exit $rc) — database not ready yet? retrying in 2s"
            sleep 2
        done
    fi
    if [ -n "${FRESHRSS_USER:-}" ]; then
        eval "set -- $(printf '%s' "$FRESHRSS_USER" | tr '\r\n' '  ')"
        set +e; php -f ./cli/create-user.php -- "$@"; rc=$?; set -e
        case "$rc" in
            0) echo "==> FreshRSS user created" ;;
            3) echo "==> FreshRSS user already exists; no change performed" ;;
            *) echo "!!! FreshRSS user creation failed (exit $rc)" >&2; exit "$rc" ;;
        esac
    fi
}

# CRON_MIN="2,32": refresh every user's feeds at those minutes, like the
# official image's crond — but on the embedded PHP, in the background.
start_cron() {
    [ -n "${CRON_MIN:-}" ] || return 0
    echo "==> feed refresh scheduled at minute(s) $CRON_MIN of every hour"
    (
        while :; do
            sleep $((60 - $(date +%S | sed 's/^0//')))
            now=$(date +%M | sed 's/^0//')
            for want in $(printf '%s' "$CRON_MIN" | tr ',' ' '); do
                if [ "$((want + 0))" -eq "$((now + 0))" ]; then
                    php ./app/actualize_script.php >/dev/null || echo "!!! feed refresh failed" >&2
                fi
            done
        done
    ) &
}

# Where is the database? With ePHPm's embedded database (compose.embedded.yml)
# it only exists once `ephpm serve` runs, so the first-run setup has to
# happen *after* the server starts; for every other backend (an external
# server, or FreshRSS's built-in SQLite) it happens before.
db_host="$(printf '%s' "${FRESHRSS_INSTALL:-}" | tr '\r\n' '  ' | sed -n 's/.*--db-host[ =]\([^ ]*\).*/\1/p')"
case "$db_host" in
    127.0.0.1*|localhost*)
        ephpm serve --config "$CONFIG" "$@" &
        pid=$!
        trap 'kill -TERM "$pid" 2>/dev/null' TERM INT
        echo "==> waiting for the embedded database at $db_host"
        i=0
        until ephpm php -r '
            mysqli_report(MYSQLI_REPORT_OFF);
            [$h, $p] = array_pad(explode(":", $argv[1], 2), 2, 3306);
            exit(@mysqli_connect($h, "root", "", "", (int) $p) ? 0 : 1);
        ' -- "$db_host" 2>/dev/null; do
            i=$((i + 1))
            [ "$i" -ge 60 ] && { echo "!!! embedded database not reachable after 60 tries" >&2; kill -TERM "$pid"; exit 1; }
            sleep 1
        done
        first_run_setup
        start_cron
        wait "$pid" || true
        trap - TERM INT
        wait "$pid"
        ;;
    *)
        first_run_setup
        start_cron
        exec ephpm serve --config "$CONFIG" "$@"
        ;;
esac
