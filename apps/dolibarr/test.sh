#!/usr/bin/env bash
# Smoke test: the entrypoint loads the schema, default data and super admin
# (the official image's DOLI_INSTALL_AUTO path, over mysqli); the admin logs
# in through the login form, creates a user through the "New user" form and
# finds it in the user list; the cron service runs the scheduled jobs.
# Runs against the MariaDB compose file.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28510
recipe_init dolibarr
export DOLI_URL_ROOT="$BASE"
export DOLI_ADMIN_PASSWORD="Recipe-pass-123"

# token PAGE-FILE — Dolibarr's CSRF token rendered into a form
token() { grep -o 'name="token" value="[^"]*' "$1" | head -n1 | sed 's/.*value="//'; }

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    echo "=== variant: $1 ==="
    compose_up
    wait_http "$BASE/" 200 600
    expect_body "$BASE/" 'name="actionlogin"'

    # 1. real workflow: log in through the login form
    local jar page loc; jar="$(cookie_jar)"; page="$(native_path "$(mktemp)")"
    curl -s -b "$jar" -c "$jar" -o "$page" "$BASE/"
    loc="$(curl -s -o /dev/null -w '%{redirect_url}' --max-time 60 -b "$jar" -c "$jar" \
        --data "token=$(token "$page")&actionlogin=login&loginfunction=loginfunction" \
        --data-urlencode "username=admin" --data-urlencode "password=$DOLI_ADMIN_PASSWORD" \
        "$BASE/index.php?mainmenu=home")"
    case "$loc" in
        *"/admin/index.php"*|*"/index.php?mainmenu=home"*) echo "==> logged in -> $loc" ;;
        *) echo "!!! login redirected to '$loc'" >&2; compose logs --tail=60 ephpm >&2; return 1 ;;
    esac

    # 2. create a user through the "New user" form and read it back
    curl -s -b "$jar" -c "$jar" -o "$page" "$BASE/user/card.php?action=create"
    loc="$(curl -s -o /dev/null -w '%{redirect_url}' --max-time 60 -b "$jar" -c "$jar" \
        --data "token=$(token "$page")&action=add&entity=1&employee=1&admin=0" \
        --data-urlencode "lastname=Ephpmrecipe" --data-urlencode "firstname=Ada" \
        --data-urlencode "login=ada.recipe" --data-urlencode "password=Recipe-pass-456" \
        "$BASE/user/card.php")"
    case "$loc" in
        *"/user/card.php?id="*) echo "==> user created -> $loc" ;;
        *) echo "!!! new-user form redirected to '$loc'" >&2; compose logs --tail=60 ephpm >&2; return 1 ;;
    esac
    expect_body "$loc" "Ephpmrecipe" -b "$jar" -c "$jar"
    expect_body "$BASE/user/list.php" "ada.recipe" -b "$jar" -c "$jar"

    # 3. the cron service ran Dolibarr's scheduled jobs with the cron key
    for _ in $(seq 1 30); do
        compose logs cron 2>/dev/null | grep "Result of run_jobs OK" >/dev/null && break
        sleep 2
    done
    compose logs cron 2>/dev/null | grep "Result of run_jobs OK" >/dev/null \
        || { echo "!!! the cron service did not run a job" >&2; compose logs --tail=30 cron >&2; return 1; }
    echo "==> cron_run_jobs.php ran a scheduled job"

    compose down -v --remove-orphans
}

run_variant compose.yml
