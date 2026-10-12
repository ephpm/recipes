#!/usr/bin/env bash
# Smoke test: wait for migrations (which seed the admin), log in through the
# Filament login form (its Livewire call), open the dashboard, save the
# threshold settings through their admin form and read them back, check the Ookla CLI
# is present, and run the scheduler once inside the scheduler service.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28402
recipe_init speedtest-tracker
export APP_URL="$BASE"
ADMIN="admin@example.com"
PASS="Recipe-Pass-9731"

# livewire_call PAGE-URL COMPONENT METHOD JSON-UPDATES — GET the page, take
# the snapshot of the Livewire component whose class name ends in COMPONENT
# plus the CSRF token, and POST a Livewire update that sets the given
# properties and calls METHOD. Prints the JSON response. The page parsing
# runs on the embedded PHP inside the container.
livewire_call() {
    local page="$1" component="$2" method="$3" updates="$4" html body
    html="$(curl -s --max-time 60 -b "$jar" -c "$jar" "$page")"
    body="$(printf '%s' "$html" | run_in ephpm ephpm php -r '
        $html = stream_get_contents(STDIN);
        preg_match_all("/wire:snapshot=\"([^\"]+)\"/", $html, $all);
        $snapshot = null;
        foreach ($all[1] as $raw) {
            $decoded = html_entity_decode($raw, ENT_QUOTES | ENT_HTML5);
            $s = json_decode($decoded, true);
            if (str_ends_with($s["memo"]["name"] ?? "", $argv[3])) { $snapshot = $decoded; break; }
        }
        if ($snapshot === null) { fwrite(STDERR, "no Livewire component named *" . $argv[3] . " on the page\n"); exit(1); }
        if (!preg_match("/data-csrf=\"([^\"]+)\"/", $html, $t)
            && !preg_match("/name=\"csrf-token\" content=\"([^\"]+)\"/", $html, $t)) { fwrite(STDERR, "no csrf token on the page\n"); exit(1); }
        if (!preg_match("/data-update-uri=\"([^\"]+)\"/", $html, $u)) { fwrite(STDERR, "no data-update-uri on the page\n"); exit(1); }
        echo $u[1], "\n";
        echo json_encode([
            "_token" => $t[1],
            "components" => [[
                "snapshot" => $snapshot,
                "updates" => json_decode($argv[2], true),
                "calls" => [["path" => "", "method" => $argv[1], "params" => []]],
            ]],
        ]), "\n";
    ' -- "$method" "$updates" "$component")" || return 1
    local uri payload
    uri="$(printf '%s\n' "$body" | sed -n 1p)"
    payload="$(printf '%s\n' "$body" | sed -n 2p)"
    curl -s --max-time 120 -b "$jar" -c "$jar" \
        -H 'Content-Type: application/json' -H 'Accept: application/json' \
        -H 'X-Livewire: true' -H "Origin: $BASE" -e "$page" \
        --data "$payload" "$uri"
}

# expect_redirect URL location-substring [curl args...]
expect_redirect() {
    local url="$1" want="$2"; shift 2
    local loc
    loc="$(curl -s -o /dev/null -w '%{redirect_url}' --max-time 60 "$@" "$url" || true)"
    case "$loc" in
        *"$want"*) echo "==> $url -> $loc" ;;
        *) echo "!!! $url redirected to '$loc' (wanted *$want*)" >&2; compose logs --tail=80 >&2 || true; return 1 ;;
    esac
}

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    echo "=== variant: $1 ==="
    compose_up
    # the login page answers 200 once migrations are done
    wait_http "$BASE/admin/login" 200 480
    # scheduled commands run as `<phpBinary()> artisan ...`; that must work (issues/pterodactyl.md)
    run_in ephpm sh -c 'b="$(ephpm php -r "require \"vendor/autoload.php\"; echo Illuminate\Console\Application::phpBinary();")"; echo "phpBinary: $b"; eval "$b artisan --version"' || { echo "!!! <phpBinary> artisan does not run: scheduled commands would silently fail" >&2; exit 1; }
    expect_redirect "$BASE/admin" "/admin/login"

    # 1. real workflow: log in through the Filament login form (Livewire)
    local jar resp
    jar="$(cookie_jar)"
    resp="$(livewire_call "$BASE/admin/login" "Login" authenticate "{\"data.email\":\"$ADMIN\",\"data.password\":\"$PASS\",\"data.remember\":false}")" || return 1
    case "$resp" in
        *'"redirect"'*) echo "==> logged in through the login form" ;;
        *) echo "!!! login did not redirect: $(printf '%s' "$resp" | head -c 800)" >&2; compose logs --tail=60 ephpm >&2; return 1 ;;
    esac
    expect_body "$BASE/admin" "Dashboard" -b "$jar" -c "$jar"

    # 2. change a record through an admin form: enable the absolute
    #    thresholds and set a download threshold on Settings -> Thresholds
    #    (a Filament settings page, saved through its Livewire `save` call),
    #    then read it back from the page and from the database
    resp="$(livewire_call "$BASE/admin/thresholds" "Thresholds" save "{\"data.absolute_enabled\":true,\"data.absolute_download\":\"417\",\"data.absolute_upload\":\"0\",\"data.absolute_ping\":\"0\"}")" || return 1
    case "$resp" in
        *'"effects"'*) echo "==> thresholds saved through the settings form" ;;
        *) echo "!!! saving the thresholds failed: $(printf '%s' "$resp" | head -c 800)" >&2; return 1 ;;
    esac
    expect_body "$BASE/admin/thresholds" 'absolute_download[^0-9]{1,40}417' -b "$jar" -c "$jar"
    local stored
    stored="$(run_in ephpm ephpm php -r '$p = new PDO("sqlite:/data/database.sqlite"); echo $p->query("SELECT payload FROM settings WHERE \"group\" = '"'"'threshold'"'"' AND name = '"'"'absolute_download'"'"'")->fetchColumn();')"
    case "$stored" in
        *417*) echo "==> the database holds absolute_download=$stored" ;;
        *) echo "!!! settings table has absolute_download='$stored'" >&2; return 1 ;;
    esac

    # 3. the Ookla CLI is installed and runnable (no network test here)
    run_in ephpm speedtest --version | sed -n 1p

    # 4. the scheduler service can run the schedule against the same database
    local out
    out="$(run_in scheduler ephpm php artisan schedule:run)"
    echo "$out" | tail -3
    case "$out" in
        *"No scheduled commands"*|*Running*) echo "==> scheduler ran artisan schedule:run" ;;
        *) echo "!!! artisan schedule:run failed in the scheduler service" >&2; return 1 ;;
    esac

    compose down -v --remove-orphans
}

run_variant compose.yml
