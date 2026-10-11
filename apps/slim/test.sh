#!/usr/bin/env bash
# Smoke test: the skeleton's routes answer through Slim's middleware stack
# (home page, JSON user list, one user, a 404 from the error handler) in
# per-request mode and in PSR-15 worker mode.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28014
recipe_init slim

run_variant() {
    COMPOSE_FILE="$DIR/$1"
    echo "=== variant: $1 ==="
    compose_up
    wait_http "$BASE/" 200 120
    expect_body "$BASE/" "Hello world"
    expect_body "$BASE/users" '"username": ?"bill.gates"'
    expect_body "$BASE/users/1" '"firstName": ?"Bill"'
    expect_status "$BASE/users/999" 404
    # the skeleton registers a catch-all OPTIONS route (CORS preflight), so an
    # unknown path answers 405 from Slim's error handler, not 404
    expect_body "$BASE/no-such-route" '"statusCode": ?405'
    # a POST body reaches the app (body-parsing middleware), echoed via the 404 handler's JSON
    expect_body "$BASE/users/1" '"statusCode": ?405' -X POST -d 'x=1'
    compose down -v --remove-orphans
}

run_variant compose.yml
run_variant compose.worker.yml
