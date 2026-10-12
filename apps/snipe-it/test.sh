#!/usr/bin/env bash
# Smoke test: run Snipe-IT's web setup wizard (pre-flight, migrate, admin
# account), log in through the login form, create a manufacturer through the
# web form and read it back, and run the scheduler once inside the scheduler
# service.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28105
recipe_init snipe-it
# The setup pre-flight compares APP_URL with the request URL.
export APP_URL="$BASE"

# csrf URL — GET the page (with the cookie jar) and print its CSRF token
csrf() {
    curl -s --max-time 60 -b "$jar" -c "$jar" "$1" \
        | sed -nE 's/.*name="_token" value="([^"]+)".*/\1/p' | sed -n 1p
}

# expect_redirect URL location-substring [curl args...] — request and check where it redirects
expect_redirect() {
    local url="$1" want="$2"; shift 2
    local loc
    loc="$(curl -s -o /dev/null -w '%{redirect_url}' --max-time 120 "$@" "$url" || true)"
    case "$loc" in
        *"$want"*) echo "==> $url -> $loc" ;;
        *) echo "!!! $url redirected to '$loc' (wanted *$want*)" >&2
           compose logs --tail=80 >&2 || true
           return 1 ;;
    esac
}

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    echo "=== variant: $1 ==="
    compose_up
    # / redirects to the setup wizard until an admin exists
    wait_http "$BASE/setup" 200 300
    # scheduled commands run as `<phpBinary()> artisan ...`; that must work (issues/pterodactyl.md)
    run_in ephpm sh -c 'b="$(ephpm php -r "require \"vendor/autoload.php\"; echo Illuminate\Console\Application::phpBinary();")"; echo "phpBinary: $b"; eval "$b artisan --version"' || { echo "!!! <phpBinary> artisan does not run: scheduled commands would silently fail" >&2; exit 1; }
    expect_redirect "$BASE/" "/setup"

    jar="$(cookie_jar)"
    local tok

    # 1. setup wizard: pre-flight, migrate (also creates the Passport keys), admin account
    expect_body "$BASE/setup" "Configuration Check" -b "$jar" -c "$jar"
    tok="$(csrf "$BASE/setup")"
    # (the migrate step is a POST; it also creates the Passport keys)
    expect_body "$BASE/setup/migrate" "Create database tables" -b "$jar" -c "$jar" --data-urlencode "_token=$tok"
    tok="$(csrf "$BASE/setup/user")"
    expect_redirect "$BASE/setup/user" "/setup/done" -b "$jar" -c "$jar" \
        --data-urlencode "_token=$tok" \
        --data "site_name=ePHPm+Recipe&first_name=Admin&last_name=User&email=admin%40example.com&username=admin&password=recipe-pass-123&password_confirmation=recipe-pass-123&email_creds=0&locale=en-US&default_currency=USD&auto_increment_assets=0"
    # setup is complete once the admin exists: the wizard now redirects home
    expect_redirect "$BASE/setup/done" "$BASE" -b "$jar" -c "$jar"

    # 2. real workflow: log in through the login form with a fresh session
    jar="$(cookie_jar)"
    tok="$(csrf "$BASE/login")"
    expect_redirect "$BASE/login" "$BASE" -b "$jar" -c "$jar" \
        --data-urlencode "_token=$tok" \
        --data "username=admin&password=recipe-pass-123"
    expect_body "$BASE/" "Dashboard" -b "$jar" -c "$jar"

    # 3. create a manufacturer through the web form and read it back
    #    (the list page is a JS table, so open the record's own page)
    tok="$(csrf "$BASE/manufacturers/create")"
    expect_redirect "$BASE/manufacturers" "/manufacturers" -b "$jar" -c "$jar" \
        --data-urlencode "_token=$tok" \
        --data-urlencode "name=ePHPm Recipe Inc"
    local id
    id="$(run_in db mariadb -N -usnipeit -psnipeit snipeit -e "select id from manufacturers where name='ePHPm Recipe Inc'" | tr -d '[:space:]')"
    [ -n "$id" ] || { echo "!!! manufacturer not found in the database" >&2; compose logs --tail=80 ephpm >&2; return 1; }
    echo "==> manufacturer #$id created through the form"
    expect_body "$BASE/manufacturers/$id" "ePHPm Recipe Inc" -b "$jar" -c "$jar"

    # 4. the scheduler service can run the schedule against the same database
    local out
    out="$(run_in scheduler ephpm php artisan schedule:run)"
    echo "$out"
    case "$out" in
        *"No scheduled commands"*|*Running*) echo "==> scheduler ran artisan schedule:run" ;;
        *) echo "!!! artisan schedule:run failed in the scheduler service" >&2; return 1 ;;
    esac

    compose down -v --remove-orphans
}

run_variant compose.yml
