# Moodle: `SERVER_PORT` is always the listen port, so a port-mapped container redirects to itself forever

**Recipe:** `apps/moodle` — **ePHPm:** `ephpm/ephpm:v0.11.3-php8.5` — **Date:** 2026-10-11

## Symptom

Moodle with `$CFG->wwwroot = 'http://127.0.0.1:28608'`, ePHPm listening on
`0.0.0.0:8080` inside the container and published as `28608:8080`: every
page answers `303` to itself (`location: http://127.0.0.1:28608/`, the
"wwwroot mismatch" page). Moodle builds the request's URL from
`HTTP_HOST` (host part only) and `SERVER_PORT`, and compares the port with
the one in `wwwroot`:

```
$_SERVER['HTTP_HOST']   = "127.0.0.1:28608"
$_SERVER['SERVER_PORT'] = "8080"          # what ePHPm sets
```

## Minimal repro

```php
<?php echo $_SERVER['SERVER_PORT'], ' ', $_SERVER['HTTP_HOST'];
```

served by `ephpm serve` on `:8080`, requested as `curl -H 'Host: example.test:9000'
http://127.0.0.1:8080/` → `8080 example.test:9000`. Apache (default
`UseCanonicalName Off`) answers `9000 example.test:9000`; nginx's
`$server_port` answers `8080` like ePHPm.

## Suspected cause

By design rather than a bug: `crates/ephpm-server/src/router.rs` stores the
listen port (`server_port: port`) and `crates/ephpm-php/src/request.rs`
passes it as `SERVER_PORT` for every request. That matches nginx +
`fastcgi_params`, but not Apache, which most PHP apps' docs (and the
`php:*-apache` based official images) assume. Apps that compare
`SERVER_PORT` against their configured URL (Moodle; anything building
absolute URLs from `SERVER_PORT`) break whenever the public port differs
from the container port — i.e. on every `-p host:container` mapping with
different numbers. An opt-in like `[server] server_port_from_host = true`
(Apache's `UseCanonicalName Off` behaviour) would let such apps run
unmodified behind a port mapping.

## Workaround in the recipe

`entrypoint.sh` reads the port from `MOODLE_WWWROOT` and starts `ephpm serve
--listen 0.0.0.0:<that port>`; `compose.yml` publishes the port 1:1
(`${EPHPM_PORT}:${EPHPM_PORT}`). Behind a TLS-terminating proxy
(`MOODLE_SSLPROXY=true`, wwwroot without a port) nothing is needed.
