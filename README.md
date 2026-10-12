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
| [laravel](apps/laravel/) | Laravel 12 skeleton | nginx + fpm, Redis cache/sessions, Octane server (worker variant) | MariaDB | yes (experimental) | tested 2026-10-11, v0.11.3-php8.5 (per-request, worker, embedded) |
| [symfony](apps/symfony/) | Symfony Demo 2.9 (Symfony 8) | nginx + fpm / Symfony CLI / FrankenPHP | MariaDB | SQLite single container (app-native) | tested 2026-10-11, v0.11.3-php8.5 (MariaDB, SQLite) |
| [bookstack](apps/bookstack/) | BookStack 26.09 | nginx + fpm (linuxserver image) | MariaDB | no (embedded DB rejects `ADD CONSTRAINT`) | tested 2026-10-11, v0.11.3-php8.5 |
| [invoiceplane](apps/invoiceplane/) | InvoicePlane 1.7 | nginx + php-fpm containers | MariaDB | no (embedded DB rejects `ALTER TABLE … MODIFY`) | tested 2026-10-11, v0.11.3-php8.5 |
| [easyappointments](apps/easyappointments/) | Easy!Appointments 1.6 | nginx + php-fpm containers | MariaDB | no (embedded DB rejects `ADD CONSTRAINT`) | tested 2026-10-11, v0.11.3-php8.5 |
| [codeigniter4](apps/codeigniter4/) | CodeIgniter 4.7 appstarter | apache/nginx + fpm, `spark serve` | MariaDB | yes (experimental) | tested 2026-10-11, v0.11.3-php8.5 (both variants) |
| [slim](apps/slim/) | Slim 4 skeleton (any PSR-15 app) | nginx + fpm, RoadRunner (worker variant via psr15-worker) | none | single container (native) | tested 2026-10-11, v0.11.3-php8.5 (per-request, worker) |
| [cakephp](apps/cakephp/) | CakePHP 5.4 app skeleton | apache/nginx + fpm, `bin/cake server` | MariaDB | no (embedded DB rejects `SHOW FULL TABLES`) | tested 2026-10-11, v0.11.3-php8.5 |
| [firefly-iii](apps/firefly-iii/) | Firefly III | official image (apache) + cron | MariaDB | see README | tested 2026-10-11, v0.11.3-php8.5 |
| [linkace](apps/linkace/) | LinkAce 2.6 | nginx + fpm (supervisord image) | MariaDB | no (schema dump DDL) | tested 2026-10-11, v0.11.3-php8.5 |
| [shaarli](apps/shaarli/) | Shaarli | nginx + fpm | flat-file | single container (native) | tested 2026-10-11, v0.11.3-php8.5 |
| [kanboard](apps/kanboard/) | Kanboard | nginx + fpm + s6 + crond | MariaDB | SQLite single container (app-native) | tested 2026-10-11, v0.11.3-php8.5 (both variants) |
| [kimai](apps/kimai/) | Kimai | `kimai2:fpm` + nginx / `kimai2:apache` | MariaDB | no | tested 2026-10-11, v0.11.3-php8.5 |
| [wallabag](apps/wallabag/) | wallabag | nginx + fpm + s6 | MariaDB | SQLite single container (app-native) | tested 2026-10-11, v0.11.3-php8.4 (both variants) |
| [shlink](apps/shlink/) | Shlink | RoadRunner (official image) / nginx + fpm | MariaDB | SQLite single container (app-native) | tested 2026-10-11, v0.11.3-php8.5 (both variants) |
| [snipe-it](apps/snipe-it/) | Snipe-IT | Apache + PHP image, Redis cache/sessions | MariaDB | no | tested 2026-10-11, v0.11.3-php8.5 |
| [privatebin](apps/privatebin/) | PrivateBin | nginx + fpm + s6 | flat-file | single container (native) | tested 2026-10-11, v0.11.3-php8.5 |
| [yourls](apps/yourls/) | YOURLS | Apache + mod_php | MariaDB | no (embedded DB rejects column-level `CHARACTER SET`) | tested 2026-10-11, v0.11.3-php8.5 |
| [wallos](apps/wallos/) | Wallos | nginx + fpm + dcron | SQLite (app-native) | single container (native) | tested 2026-10-11, v0.11.3-php8.5 |
| [freshrss](apps/freshrss/) | FreshRSS | Apache + mod_php + crond | PostgreSQL | SQLite single container (app-native) | tested 2026-10-11, v0.11.3-php8.5 (both variants) |
| [castopod](apps/castopod/) | Castopod | FrankenPHP + supercronic (s6) | MariaDB | no | tested 2026-10-11, v0.11.3-php8.4 |
| [movary](apps/movary/) | Movary | nginx + fpm + job worker (supervisord) | MariaDB | SQLite single container (app-native) | tested 2026-10-11, v0.11.3-php8.5 (both variants) |
| [phpmyadmin](apps/phpmyadmin/) | phpMyAdmin | Apache + mod_php | MariaDB (managed) | — | tested 2026-10-11, v0.11.3-php8.5 (with a `ResponseRenderer` patch, see README) |
| [dokuwiki](apps/dokuwiki/) | DokuWiki | Apache/nginx + fpm | flat-file | single container (native) | tested 2026-10-11, v0.11.3-php8.5 |
| [invoiceninja](apps/invoiceninja/) | Invoice Ninja 5 | fpm image + nginx, Redis | MariaDB | no | tested 2026-10-11, v0.11.3-php8.5 |
| [espocrm](apps/espocrm/) | EspoCRM | official image (apache/fpm) + daemon container | MariaDB | no | tested 2026-10-11, v0.11.3-php8.4 |
| [akaunting](apps/akaunting/) | Akaunting | nginx/apache + fpm, Redis | MariaDB | no | tested 2026-10-11, v0.11.3-php8.3 |
| [koillection](apps/koillection/) | Koillection | FrankenPHP (worker) | PostgreSQL | MariaDB variant | tested 2026-10-11, v0.11.3-php8.5 (PostgreSQL, MariaDB) |
| [adminer](apps/adminer/) | Adminer | `php -S` (official image) | MariaDB (managed) | — | tested 2026-10-11, v0.11.3-php8.5 |
| [mediawiki](apps/mediawiki/) | MediaWiki | Apache + mod_php | MariaDB | SQLite single container (app-native) | tested 2026-10-11, v0.11.3-php8.5 (both variants) |
| [part-db](apps/part-db/) | Part-DB | Apache + fpm | MariaDB | SQLite single container (app-native) | tested 2026-10-11, v0.11.3-php8.5 (both variants) |
| [pelican](apps/pelican/) | Pelican Panel | Caddy + fpm + supervisord (scheduler, queue) | SQLite (app-native) | single container + scheduler/queue sidecars | tested 2026-10-11, v0.11.3-php8.5 |
| [matomo](apps/matomo/) | Matomo | Apache + mod_php / nginx + fpm | MariaDB | no | tested 2026-10-11, v0.11.3-php8.5 |
| [mantisbt](apps/mantisbt/) | MantisBT 2.28 | Apache + mod_php / nginx + fpm | MariaDB | no (untried) | tested 2026-10-12, v0.11.3-php8.5 |
| [koel](apps/koel/) | Koel 9.15 | nginx + fpm | MariaDB | — | **blocked** — ePHPm's GD has no JPEG/WebP (installer refuses to run) |
| [monica](apps/monica/) | Monica 4 | Apache + mod_php + cron, Redis | MariaDB | — | **blocked** — ePHPm's GD has no FreeType (creating a contact answers 500) |

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
