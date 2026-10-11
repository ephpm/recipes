# ePHPm recipes

Tested, ready-to-run recipes for running popular open-source PHP applications
and frameworks on [ePHPm](https://github.com/ephpm/ephpm), the single-binary
PHP application server. Each recipe replaces the usual nginx/apache +
php-fpm (+ Redis, + optionally MySQL) stack with **one ePHPm container**.

* `apps/<name>/` — one directory per application: a `Dockerfile` built `FROM
  ephpm/ephpm:<pinned tag>`, an `ephpm.toml`, a `compose.yml` with the app's
  real database, a README with what it replaces and what to watch for, and a
  `test.sh` smoke test that CI runs on every push.
* Where it makes sense a second `compose.embedded.yml` runs the app as a
  **single container** on ePHPm's embedded MySQL-compatible database (the
  Turso engine — Beta upstream, so this variant is always labelled
  experimental) with the built-in KV store standing in for Redis
  cache/sessions. Redis used as a *queue broker* stays a real Redis.
* `candidates.csv` — the survey of 250+ active PHP web apps this list is
  drawn from, with each one's deployment method, database, PHP/extension
  requirements and whether it fits ePHPm.
* `ISSUES.md` — ePHPm bugs and gaps found while writing recipes.
* `UPSTREAM.md` — proposed additions to upstream projects' own docs.

## Using a recipe

```bash
git clone https://github.com/ephpm/recipes
cd recipes/apps/wordpress
docker compose up -d          # podman compose works too
open http://localhost:8080    # EPHPM_PORT=8090 to use another host port
```

Every recipe's README says which environment variables it reads (they match
the app's official image where one exists), how to run the app's CLI through
the embedded PHP (`docker compose exec ephpm ephpm php ...`), and what is
known not to work.

## Status

"tested" means the smoke test in `test.sh` was run on the ePHPm tag shown,
on the date shown: the image builds, the app installs, the home page answers
200, and one real workflow (log in / create a record) succeeds. Anything else
is untested, and the README says so.

| Recipe | App | Replaces | Default DB | Embedded variant | Status |
|---|---|---|---|---|---|
| [wordpress](apps/wordpress/) | WordPress 7.1 | nginx/apache + fpm, Redis object cache | MariaDB | yes (experimental) | tested 2026-10-11, v0.11.3-php8.5 |

## Running the smoke tests locally

```bash
bash apps/wordpress/test.sh                      # docker compose
COMPOSE="podman compose" bash apps/wordpress/test.sh
KEEP=1 bash apps/wordpress/test.sh               # leave the stack running
```

Each test uses the compose project name `recipes-<app>` and tears down its
containers, volumes and built images when it finishes. `lib/harness.sh` has
the helpers.

## Conventions

* Images are pinned to a real `ephpm/ephpm` tag (`v0.11.3-php8.5` today;
  `EPHPM_TAG` build arg). Never `latest`.
* Config keys are verified against ePHPm's
  [configuration reference](https://ephpm.dev/reference/config/); unknown keys
  are a startup error in ePHPm, so every `ephpm.toml` here starts.
* Worker mode (`[php] mode = "worker"`) is used only where the app has a
  supported adapter (Laravel via `ephpm/octane-driver`, PSR-15 apps via
  `ephpm/psr15-worker`). Everything else runs in the default per-request mode.
* Compose services are named `ephpm` (the app) and `db`; the app's CLI is
  reachable with `docker compose exec ephpm ...`.
