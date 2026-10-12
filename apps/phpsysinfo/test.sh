#!/usr/bin/env bash
# Smoke test: home page, the XML data endpoint (hostname, CPU and memory
# sections come from /proc), the JSON endpoint, private config refused.
# shellcheck source=../../lib/harness.sh
source "$(dirname "$0")/../../lib/harness.sh"
DEFAULT_PORT=28172
recipe_init phpsysinfo
compose_up
wait_http "$BASE/" 200 120
expect_body "$BASE/" "phpSysInfo"
expect_body "$BASE/xml.php?plugin=complete&json" "Hostname|Vitals"
expect_body "$BASE/xml.php?plugin=complete" "<Vitals"
expect_body "$BASE/xml.php?plugin=complete" "<Memory"
expect_status "$BASE/phpsysinfo.ini" 403
