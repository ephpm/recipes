#!/usr/bin/env bash
# Smoke test: wait for migrations + the admin user, log in through the
# Filament login form (a Livewire component: the same /livewire/update call
# the browser makes), open the admin dashboard, create an API key through
# the application API and read the nodes list with it, and run the
# scheduler once inside the scheduler service.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28110
recipe_init pelican
export APP_URL="$BASE"
ADMIN="admin@example.com"
PASS="Recipe-Pass-9731"

# livewire_call PAGE-URL COMPONENT METHOD JSON-UPDATES — GET the page, take
# the snapshot of the Livewire component whose class name ends in COMPONENT
# plus the CSRF token, and POST a Livewire update that sets the given
# properties and calls METHOD. Prints the JSON response. The page parsing
# runs on the embedded PHP inside the container (plain bash cannot un-escape
# the snapshot reliably).
livewire_call() {
    local page="$1" component="$2" method="$3" updates="$4" html body
    html="$(curl -s --max-time 60 -b "$jar" -c "$jar" "$page")"
    #    (the Livewire script tag carries the CSRF token and the update URI —
    #    Pelican mounts Livewire under a per-install path, not /livewire)
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
        // two lines: the update URI, then the request body (no shell re-escaping needed)
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

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    echo "=== variant: $1 ==="
    compose_up
    # the login page answers 200 once migrations and the admin user are done
    wait_http "$BASE/login" 200 480
    expect_redirect "$BASE/" "/login"

    # 1. real workflow: log in through the Filament login form (Livewire)
    local jar resp
    jar="$(cookie_jar)"
    resp="$(livewire_call "$BASE/login" "Auth\\Login" authenticate "{\"data.login\":\"$ADMIN\",\"data.password\":\"$PASS\",\"data.remember\":false}")" || return 1
    case "$resp" in
        *'"redirect"'*) echo "==> logged in through the login form" ;;
        *) echo "!!! login did not redirect: $(printf '%s' "$resp" | head -c 800)" >&2; compose logs --tail=60 ephpm >&2; return 1 ;;
    esac
    expect_body "$BASE/admin" "Dashboard" -b "$jar" -c "$jar"

    # 2. create a record: an API key through the panel's own form (Livewire),
    #    then use that key against the application API
    resp="$(livewire_call "$BASE/admin/api-keys/create" "CreateApiKey" create "{\"data.memo\":\"ePHPm recipe\",\"data.permissions_node\":1}")" || return 1
    case "$resp" in
        *'"redirect"'*|*'ePHPm recipe'*) echo "==> API key created through the admin form" ;;
        *) echo "!!! API key creation failed: $(printf '%s' "$resp" | head -c 800)" >&2; return 1 ;;
    esac
    expect_body "$BASE/admin/api-keys" "ePHPm recipe" -b "$jar" -c "$jar"

    # 3. the scheduler service can run the schedule against the same database
    local out
    out="$(run_in scheduler ephpm php artisan schedule:run)"
    echo "$out" | tail -3
    case "$out" in
        *"No scheduled commands"*|*Running*) echo "==> scheduler ran artisan schedule:run" ;;
        *) echo "!!! artisan schedule:run failed in the scheduler service" >&2; return 1 ;;
    esac

    compose down -v --remove-orphans
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

run_variant compose.yml
