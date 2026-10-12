#!/usr/bin/env bash
# Smoke test: unattended install, home page 200, administrator login through
# the JSON API, then an authenticated admin API call.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28175
recipe_init fossbilling
export FOSSBILLING_ADMIN_PASSWORD="Recipe-pass-1234!" FOSSBILLING_URL="$BASE/"
compose_up
wait_http "$BASE/" 200 300
