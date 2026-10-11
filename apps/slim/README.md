# Slim 4 (PSR-15) on ePHPm

| | |
|---|---|
| App | [Slim-Skeleton](https://github.com/slimphp/Slim-Skeleton) (Slim 4.15, PHP-DI, Monolog) — `SLIM_VERSION` build arg |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | nginx + php-fpm; RoadRunner/FrankenPHP for the worker variant |
| Default stack | `compose.yml` — single container, per-request mode (the skeleton has no database) |
| Worker mode | `compose.worker.yml` — persistent workers through `ephpm/psr15-worker` |
| Status | tested 2026-10-11 on v0.11.3-php8.5 (both variants): home page, `/users` and `/users/1` JSON from the container-wired repository, 404/405 from Slim's error handler, POST body parsed |

The recipe applies to any **PSR-15** application (Slim, Mezzio, Yii3, a
hand-rolled pipeline): replace the `composer create-project` line in the
`Dockerfile` with `COPY . /app` + `composer install` and make
`worker-bootstrap.php` return your `RequestHandlerInterface`.

## What changes versus nginx + php-fpm

* **One process.** `[server] fallback = ["$uri", "/index.php?$query_string"]`
  in `ephpm.toml` is `try_files $uri /index.php$is_args$args`.
* **Worker mode without RoadRunner.** `ephpm.worker.toml` sets
  `[php] mode = "worker"` and `[php.worker] script = "vendor/bin/ephpm-worker"`
  — the [`ephpm/psr15-worker`](https://github.com/ephpm/psr15-worker)
  adapter. `worker-bootstrap.php` (pointed at by `EPHPM_WORKER_BOOTSTRAP`)
  builds the app exactly as `public/index.php` does but returns it; the
  adapter converts ePHPm's request envelope to PSR-7 and calls
  `$app->handle()` in a loop, one booted app per worker thread. See the
  [PSR-15 worker guide](https://ephpm.dev/guides/psr15-worker/).
* Nothing else changes: the same `app/` settings, dependencies, middleware
  and routes files are used by both modes.

## Run

```bash
docker compose up -d                        # per-request
docker compose -f compose.worker.yml up -d  # worker mode
curl http://localhost:8080/users
```

## Configuration notes

* In worker mode `document_root` is the project root (the worker script must
  live under it); `blocked_paths` keeps `app/`, `vendor/`, `logs/` and the
  bootstrap off the web, and every non-static request goes to the booted app.
* Worker-mode hygiene: do not keep per-request state in container
  singletons; the skeleton's in-memory user repository is a singleton by
  design and is fine. `[php.worker] max_requests` recycles workers as a leak
  guard.
* The skeleton's catch-all `OPTIONS /{routes:.*}` route makes unknown paths
  answer `405` rather than `404`; that is the skeleton, not ePHPm.
* `display_errors` is forced Off in both configs (v0.11.3 otherwise prints
  PHP deprecations into responses — the skeleton triggers one on PHP 8.5).

## Known limitations

* The skeleton pins `monolog/monolog ^2` and `php-di/php-di ^6`; on PHP 8.5 a
  deprecation is logged (not displayed). Upgrade the dependencies in your
  own app.
