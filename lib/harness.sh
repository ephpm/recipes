#!/usr/bin/env bash
# Shared smoke-test helpers for every recipe's test.sh.
#
# Usage (from apps/<name>/test.sh):
#
#   source "$(dirname "$0")/../../lib/harness.sh"
#   recipe_init "<name>"            # sets $APP, $PROJECT, $COMPOSE, $PORT, $BASE
#   compose_up                      # builds + starts compose.yml as project recipes-<name>
#   wait_http "$BASE/" 200 180      # poll until the home page answers 200
#   ... one real workflow ...
#   recipe_done                     # tears everything down (also runs on failure)
#
# Environment:
#   COMPOSE        compose command (default: "docker compose"; use "podman compose" locally)
#   COMPOSE_FILE   compose file to use (default: compose.yml in the recipe directory)
#   RECIPE_PORT    host port to publish ePHPm on (default: the recipe's own default)
#   KEEP=1         do not tear down on exit (for debugging)
#   NO_BUILD=1     skip the image build (reuse an existing image)

set -euo pipefail

# Git Bash on Windows: make sure the GNU coreutils/grep win over anything
# else on PATH (a stray grep.exe garbles flags).
case "$(uname -s)" in MINGW*|MSYS*) PATH="/usr/bin:$PATH" ;; esac

recipe_init() {
    APP="$1"
    DIR="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
    PROJECT="recipes-${APP}"
    COMPOSE="${COMPOSE:-docker compose}"
    COMPOSE_FILE="${COMPOSE_FILE:-${DIR}/compose.yml}"
    PORT="${RECIPE_PORT:-${DEFAULT_PORT:-8080}}"
    BASE="http://127.0.0.1:${PORT}"
    export EPHPM_PORT="$PORT"
    export APP PROJECT DIR BASE
    trap 'recipe_done' EXIT
    echo "==> [$APP] project=$PROJECT port=$PORT compose='$COMPOSE' file=$COMPOSE_FILE"
}

# Path handed to the compose binary. On Windows (Git Bash driving a native
# docker-compose.exe) that must be a Windows path, not /c/....
compose_path() {
    if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi
}

# A path both native Windows tools (curl.exe) and the MSYS tools (grep) can
# open: C:/Users/... on Git Bash, unchanged elsewhere.
native_path() {
    if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi
}

# cookie_jar — prints the path of a fresh temp file usable as `curl -c/-b`
# on every platform (on Git Bash the MSYS /tmp/... path is silently
# written elsewhere by the native curl, so hand it a native path).
cookie_jar() {
    native_path "$(mktemp)"
}

compose() {
    # shellcheck disable=SC2086
    $COMPOSE -p "$PROJECT" -f "$(compose_path "$COMPOSE_FILE")" "$@"
}

compose_up() {
    if [ "${NO_BUILD:-0}" != "1" ]; then
        # No --pull: every base image is pinned by tag, and re-pulling on each
        # build burns through Docker Hub's anonymous pull rate limit.
        compose build "$@"
    fi
    compose up -d "$@"
}

# wait_http URL [expected-status] [timeout-seconds]
wait_http() {
    local url="$1" want="${2:-200}" timeout="${3:-120}" code="" i=0
    while [ "$i" -lt "$timeout" ]; do
        code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$url" || true)"
        if [ "$code" = "$want" ]; then
            echo "==> $url -> $code (after ${i}s)"
            return 0
        fi
        sleep 1
        i=$((i + 1))
    done
    echo "!!! $url -> $code (wanted $want) after ${timeout}s" >&2
    compose logs --tail=80 >&2 || true
    return 1
}

# expect_status URL expected-status [curl args...]
expect_status() {
    local url="$1" want="$2"; shift 2
    local code
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 "$@" "$url" || true)"
    if [ "$code" != "$want" ]; then
        echo "!!! $url -> $code (wanted $want)" >&2
        compose logs --tail=80 >&2 || true
        return 1
    fi
    echo "==> $url -> $code"
}

# expect_body URL grep-pattern [curl args...]
expect_body() {
    local url="$1" pat="$2"; shift 2
    # Body captured first, and grep without -q: under pipefail, a grep that
    # exits on the first match makes the writer die of SIGPIPE and the
    # pipeline fail even though the pattern matched.
    local body
    body="$(curl -s --max-time 30 "$@" "$url" || true)"
    if ! printf '%s' "$body" | grep -E -- "$pat" >/dev/null; then
        echo "!!! $url body does not match /$pat/" >&2
        printf '%s' "$body" | head -c 2000 >&2 || true
        compose logs --tail=80 >&2 || true
        return 1
    fi
    echo "==> $url body matches /$pat/"
}

# form_value URL FIELD [curl args...] — print the value attribute of the
# first <input name="FIELD" ...> on the page (CSRF tokens, nonces). Pass
# `-c "$jar" -b "$jar"` so the token matches the session cookie.
form_value() {
    local url="$1" name="$2"; shift 2
    local body
    body="$(curl -s --max-time 30 "$@" "$url" || true)"
    printf '%s' "$body" \
        | grep -oE "<input[^>]*name=[\"']${name}[\"'][^>]*>" \
        | sed -nE 's/.*value=["'"'"']([^"'"'"']*)["'"'"'].*/\1/p' \
        | awk 'NR==1' || true      # no match prints nothing; never fails the caller under set -e
}

# run_in SERVICE CMD... — exec inside a compose service
run_in() {
    local svc="$1"; shift
    compose exec -T "$svc" "$@"
}

# copy_in SERVICE LOCAL-FILE CONTAINER-PATH — copy a file into a service
copy_in() {
    compose cp "$(compose_path "$2")" "$1:$3"
}

recipe_done() {
    local rc=$?
    trap - EXIT
    if [ "${KEEP:-0}" = "1" ]; then
        echo "==> KEEP=1: leaving $PROJECT running"
    else
        compose down -v --remove-orphans >/dev/null 2>&1 || true
        if [ "${KEEP_IMAGES:-0}" != "1" ]; then
            docker_images_rm
        fi
    fi
    if [ "$rc" -eq 0 ]; then echo "==> [$APP] PASS"; else echo "==> [$APP] FAIL (rc=$rc)"; fi
    exit "$rc"
}

docker_images_rm() {
    # Remove the images this project built (never the base ephpm/db images).
    local engine
    engine="${COMPOSE%% *}"
    "$engine" images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null \
        | grep -E "(^|/)${PROJECT}([-_:]|$)" \
        | xargs -r "$engine" rmi -f >/dev/null 2>&1 || true
}
