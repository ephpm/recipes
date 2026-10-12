#!/usr/bin/env bash
# Smoke test (does NOT pass on v0.11.3 — see README "Status"): wait for
# migrate + the demo seed, check the panel's login page and assets, read the
# seeded admin and a seeded product back through Eloquent, and run the
# demo's scheduled task through Laravel's scheduler (`schedule:test`), which
# spawns `<PHP binary> artisan app:reset-demo-database` in the scheduler
# sidecar.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28521
recipe_init filament-demo
export APP_URL="$BASE"

compose_up
wait_http "$BASE/login" 200 900
fx="$(curl -s --max-time 30 "$BASE/info.php" || true)"; case "$fx" in *phpinfo*) echo "!!! the base image's info.php fixture is served" >&2; exit 1 ;; esac
expect_status "$BASE/build/manifest.json" 200
expect_body "$BASE/login" 'wire:snapshot'                 # the Livewire login component

# the seed ran: admin user and products with their images
tinker() { run_in ephpm ephpm php artisan tinker --execute "$1" 2>/dev/null | tail -n 1; }
[ "$(tinker 'echo App\Models\User::where("email","admin@filamentphp.com")->count();')" = "1" ] \
    || { echo "!!! the demo admin user was not seeded" >&2; exit 1; }
n="$(tinker 'echo App\Models\Shop\Product::has("media")->count();')"
[ "${n:-0}" -gt 0 ] || { echo "!!! no seeded product has an image" >&2; exit 1; }
echo "==> seeded: admin user, $n products with images"

# the scheduler: the scheduled command is spawned as `<phpBinary()> artisan ...`
out="$(run_in scheduler ephpm php artisan schedule:test --name=app:reset-demo-database --no-interaction 2>&1)" \
    || { echo "!!! schedule:test failed: $out" >&2; exit 1; }
case "$out" in
    *"has been reset"*|*DONE*) echo "==> scheduler ran app:reset-demo-database" ;;
    *) echo "!!! unexpected schedule:test output:" >&2; echo "$out" | tail -20 >&2; exit 1 ;;
esac
[ "$(tinker 'echo App\Models\User::count() > 0 ? "ok" : "empty";')" = "ok" ] \
    || { echo "!!! the database is empty after the reset" >&2; exit 1; }
