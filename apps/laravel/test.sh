#!/usr/bin/env bash
# Smoke test: the skeleton's welcome page answers, migrations ran, and a
# real round trip through the framework works — a session cookie is issued
# and stored in the KV store, and a record is written through Eloquent
# (artisan tinker) and read back over HTTP. Runs the MariaDB stack, the
# worker-mode stack, and the single-container embedded variant.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28011
recipe_init laravel

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    echo "=== variant: $1 ==="
    compose_up
    wait_http "$BASE/up" 200 180            # Laravel's health route
    # scheduled commands run as `<phpBinary()> artisan ...`; that must work (issues/pterodactyl.md)
    run_in ephpm sh -c 'b="$(ephpm php -r "require \"vendor/autoload.php\"; echo Illuminate\Console\Application::phpBinary();")"; echo "phpBinary: $b"; eval "$b artisan --version"' || { echo "!!! <phpBinary> artisan does not run: scheduled commands would silently fail" >&2; exit 1; }
    expect_body "$BASE/" "Laravel"

    # Migrations ran (the embedded variant migrates in the background after start).
    local i=0
    until run_in ephpm ephpm php artisan migrate:status 2>/dev/null | grep "Ran" >/dev/null; do
        i=$((i + 1)); [ "$i" -ge 60 ] && { echo "!!! migrations did not run"; compose logs --tail=60 ephpm; return 1; }
        sleep 2
    done
    echo "==> migrations present"

    # Session round trip: /up issues no cookie, so hit a route that starts a
    # session — the welcome page sets laravel_session + XSRF-TOKEN.
    local jar; jar="$(cookie_jar)"
    curl -s -o /dev/null -c "$jar" "$BASE/"
    grep -qi "session" "$jar" || { echo "!!! no session cookie"; rm -f "$jar"; return 1; }
    rm -f "$jar"
    run_in ephpm ephpm kv keys '*' | grep . >/dev/null || { echo "!!! no keys in the KV store (sessions/cache not on ePHPm)"; return 1; }
    echo "==> session issued and stored in the KV store"

    # Write a record through Eloquent and read it back over HTTP.
    run_in ephpm ephpm php artisan tinker --execute \
        'App\Models\User::create(["name"=>"Recipe","email"=>"recipe@example.com","password"=>bcrypt("secret")]); echo App\Models\User::count();' \
        | grep -E '^1' >/dev/null || { echo "!!! Eloquent insert failed"; return 1; }
    if [ "$1" = "compose.worker.yml" ]; then
        # Worker mode routes every non-static request through the booted
        # application, so a stray PHP file in public/ is not executed; read
        # the record back through the framework instead.
        run_in ephpm ephpm php artisan tinker --execute 'echo App\Models\User::first()->email;' \
            | grep 'recipe@example.com' >/dev/null || { echo "!!! read-back failed"; return 1; }
        echo "==> record read back through the framework"
    else
        copy_in ephpm "$DIR/probe/recipe-probe.php" /app/public/recipe-probe.php
        expect_body "$BASE/recipe-probe.php" "recipe@example.com"
        run_in ephpm rm -f /app/public/recipe-probe.php
    fi

    compose down -v --remove-orphans
}

run_variant compose.yml
run_variant compose.worker.yml
run_variant compose.embedded.yml
