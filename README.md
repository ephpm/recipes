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
| [projectsend](apps/projectsend/) | ProjectSend 2.7 | nginx + fpm + queue worker + scheduler | MySQL | no (untried) | tested 2026-10-12, v0.11.3-php8.5 |
| [aimeos](apps/aimeos/) | Aimeos shop distribution aimeos/aimeos and the crontab running art...| compose.yml — ePHPm + jobs sidecar (same image) + MariaDB 11 | see README | tested 2026-10-12, v0.11.3-php8.5 |
| [ampache](apps/ampache/) | Ampache 8.2.2 (AMPACHE_VERSION build arg; the _all_php8.5 relea | the ampache/ampache image (Apache + mod_php + cron under superviso...| compose.yml — ePHPm + a cron service on the same image + MariaDB...| see README | tested 2026-10-12, v0.11.3-php8.5 |
| [bagisto](apps/bagisto/) | Bagisto v2.5.0 (BAGISTO_VERSION build arg) — Laravel 13 | a nginx/apache + php-fpm host and the cron entry for the Laravel s...| compose.yml — ePHPm + the scheduler (same image) + MariaDB 11 | see README | tested 2026-10-12, v0.11.3-php8.5 |
| [cachet](apps/cachet/) | Cachet 3.x (cachethq/cachet commit 40bd081, CACHET_REF build  | Cachet's docker image (nginx + php-fpm, supervisord running the sc...| compose.yml — ePHPm + scheduler + queue worker (same image) + Ma...| see README | tested 2026-10-12, v0.11.3-php8.5 |
| [directorylister](apps/directorylister/) | Directory Lister 5.7.0 (DL_VERSION build arg) | a web server (Apache/nginx) + php-fpm in front of the release (the...| compose.yml — one ePHPm container, the listed files in a volume ...| see README | tested 2026-10-12, v0.11.3-php8.5 |
| [dolibarr](apps/dolibarr/) | Dolibarr 24.0.2 (DOLI_VERSION build arg) | the official dolibarr/dolibarr image (php-apache + the mysql clien...| compose.yml — ePHPm + cron (same image) + MariaDB 11 | see README | tested 2026-10-12, v0.11.3-php8.4 |
| [drupal](apps/drupal/) | Drupal 11.4.9 (drupal/recommended-project, DRUPAL_VERSION bu | Apache + mod_php (the official drupal image) | compose.yml — ePHPm + MariaDB 11 | see README | tested 2026-10-12, v0.11.3-php8.5 |
| [elgg](apps/elgg/) | Elgg 7.1.1 (ELGG_VERSION build arg) | Apache (install/config/htaccess.dist) or nginx (nginx.dist) + php-...| compose.yml — ePHPm + a cron service on the same image + MariaDB...| see README | tested 2026-10-12, v0.11.3-php8.5 |
| [filegator](apps/filegator/) | FileGator 7.16.5 (FILEGATOR_VERSION build arg) | Apache + mod_php (the official filegator/filegator image) | compose.yml — one ePHPm container; files in the repository volum...| see README | tested 2026-10-12, v0.11.3-php8.5 |
| [flarum](apps/flarum/) | Flarum 2.0 (flarum/flarum skeleton, FLARUM_VERSION build arg) wi | nginx + php-fpm (the mondedie/flarum / crazymax/flarum images) | compose.yml — ePHPm + MariaDB 11 | see README | tested 2026-10-12, v0.11.3-php8.5 |
| [freescout](apps/freescout/) | FreeScout 1.8.247 (FREESCOUT_VERSION build arg) | Apache/nginx + php-fpm + the * * * * * php artisan schedule:run cr...| compose.yml — ePHPm + scheduler + queue worker (same image) + Ma...| see README | tested 2026-10-12, v0.11.3-php8.5 |
| [fusio](apps/fusio/) | Fusio 7.2.0 (fusio/impl 8.8.9; FUSIO_VERSION build ar | the official fusio/fusio image: Apache + mod_php + cron + supervis...| compose.yml — ePHPm + cron and worker sidecars (same image) + Ma...| see README | tested 2026-10-12, v0.11.3-php8.5 |
| [glpi](apps/glpi/) | GLPI 12.0.0 (GLPI_VERSION build arg) | Apache + mod_php + supervisord (running the GLPI cron) — the off...| compose.yml — ePHPm + cron sidecar (same image) + MariaDB 11 | see README | tested 2026-10-12, v0.11.3-php8.5 |
| [grav](apps/grav/) | Grav 2.2.6, the grav-admin package (admin2 panel + API plugin) ( | Apache/nginx + php-fpm (the linuxserver/grav image) | compose.yml — one container; Grav is flat-file, no database | see README | tested 2026-10-12, v0.11.3-php8.5 |
| [grocy](apps/grocy/) | Grocy 4.7.1 (GROCY_VERSION build arg; requires PHP 8.5) | the linuxserver/grocy image (nginx + php-fpm + s6) | compose.yml — one container; Grocy's own SQLite database in the ...| see README | tested 2026-10-12, v0.11.3-php8.5 |
| [heimdall](apps/heimdall/) | Heimdall v2.8.3 (HEIMDALL_VERSION build arg)  | the linuxserver/heimdall image (nginx + php-fpm + s6) | compose.yml — one container, SQLite in the data volume (upstream...| see README | tested 2026-10-12, v0.11.3-php8.5 |
| [invoiceshelf](apps/invoiceshelf/) | InvoiceShelf 2.4.6 (INVOICESHELF_VERSION build arg) — Lara | the invoiceshelf/invoiceshelf image (nginx + php-fpm + cron) | compose.yml — ePHPm + a scheduler service on the same image + Ma...| see README | tested 2026-10-12, v0.11.3-php8.5 |
| [joomla](apps/joomla/) | Joomla! 6.1.4 (JOOMLA_VERSION build arg) | Apache + mod_php (the official joomla image) | compose.yml — ePHPm + MariaDB 11 | see README | tested 2026-10-12, v0.11.3-php8.5 |
| [krayin](apps/krayin/) | Krayin CRM v2.2.6 (KRAYIN_VERSION build arg) — Laravel 12 | a nginx/apache + php-fpm host and the cron entry for the Laravel s...| compose.yml — ePHPm + the scheduler (same image) + MariaDB 11 | see README | tested 2026-10-12, v0.11.3-php8.5 |
| [librespeed](apps/librespeed/) | LibreSpeed v6.3.0 (LIBRESPEED_VERSION build a | Apache + mod_php (the ghcr.io/librespeed/speedtest image) | compose.yml — ePHPm + MariaDB 11 (results / telemetry database) | see README | tested 2026-10-12, v0.11.3-php8.5 |
| [limesurvey](apps/limesurvey/) | LimeSurvey 7.5.0 (LIMESURVEY_VERSION build arg) | Apache + mod_php (the widely used martialblog/limesurvey image) | compose.yml — ePHPm + MariaDB 11 | see README | tested 2026-10-12, v0.11.3-php8.5 |
| [mautic](apps/mautic/) | Mautic 7.2.1 (mautic/recommended-project, MAUTIC_VERSION build a | the official mautic/mautic image in its three roles — mautic_web...| compose.yml — ePHPm (web) + cron + worker (same image) + MariaDB...| see README | tested 2026-10-12, v0.11.3-php8.4 |
| [moodle](apps/moodle/) | Moodle 5.3.0 (MOODLE_VERSION build arg, a git tag) | Apache/nginx + php-fpm + the system crontab entry for admin/cli/cr...| compose.yml — ePHPm + cron sidecar (same image) + PostgreSQL 17 | see README | tested 2026-10-12, v0.11.3-php8.5 |
| [nextcloud](apps/nextcloud/) | Nextcloud server 35.0.1 (NEXTCLOUD_VERSION build arg; 35 is the | the nextcloud:apache image (Apache + mod_php), or nextcloud:fpm + ...| compose.yml — ePHPm + a background-jobs sidecar + MariaDB 11 | see README | tested 2026-10-12, v0.11.3-php8.5 |
| [ojs](apps/ojs/) | OJS 3.5.0-4 (OJS_VERSION build arg) | the official pkp/ojs image (php-apache with AcceptPathInfo + mod_r...| compose.yml — ePHPm + the scheduled-tasks runner + MariaDB 11 | see README | tested 2026-10-12, v0.11.3-php8.4 |
| [open-web-analytics](apps/open-web-analytics/) | Open Web Analytics 1.14.0 (OWA_VERSION build arg) | Apache/nginx + php-fpm, and the crontab entry for php cli.php cmd=...| compose.yml — ePHPm + a cron service on the same image + MariaDB...| see README | tested 2026-10-12, v0.11.3-php8.5 |
| [opensourcepos](apps/opensourcepos/) | Open Source Point of Sale 3.4.2 (OSPOS_ | the jekkos/opensourcepos image (Apache + mod_php) | compose.yml — ePHPm + MariaDB 11 | see README | tested 2026-10-12, v0.11.3-php8.4 |
| [piwigo](apps/piwigo/) | Piwigo 16.4.0 (PIWIGO_VERSION build arg) | Apache/nginx + php-fpm (the linuxserver/piwigo image) | compose.yml — ePHPm + MariaDB 11 | see README | tested 2026-10-12, v0.11.3-php8.5 |
| [pterodactyl](apps/pterodactyl/) | Pterodactyl Panel v1.15.1 (PTERODACTYL_VERSION build arg) —  | nginx + php-fpm + supervisord (queue worker) + crond (scheduler) �...| compose.yml — ePHPm + queue worker + scheduler (same image) + Ma...| see README | tested 2026-10-12, v0.11.3-php8.5 |
| [roundcube](apps/roundcube/) | Roundcube 1.7.4 (ROUNDCUBE_VERSION build arg) | Apache + mod_php (the roundcube/roundcubemail image) | compose.yml — ePHPm + MariaDB 11 + a throwaway test mail server ...| see README | tested 2026-10-12, v0.11.3-php8.5 |
| [rss-bridge](apps/rss-bridge/) | RSS-Bridge release 2025-08-05 (RSSBRIDGE_VE | the rssbridge/rss-bridge image (nginx + php-fpm) | compose.yml — one container, no database (file cache) | see README | tested 2026-10-12, v0.11.3-php8.5 |
| [selfoss](apps/selfoss/) | selfoss 2.19 (SELFOSS_VERSION build arg; the latest tagged r | Apache with selfoss's .htaccess (or nginx + php-fpm), and the cron...| compose.yml — ePHPm + an updater service on the same image; self...| see README | tested 2026-10-12, v0.11.3-php8.5 |
| [solidinvoice](apps/solidinvoice/) | SolidInvoice 3.0.1 (SOLIDINVOICE_VERSION build arg) | the official solidinvoice/solidinvoice image (a static FrankenPHP ...| compose.yml — ePHPm + MariaDB 11 | see README | tested 2026-10-12, v0.11.3-php8.4 |
| [speedtest-tracker](apps/speedtest-tracker/) | Speedtest Tracker v1.15.0 (SPEEDTEST_TRACKER_VERSION bu | the linuxserver/speedtest-tracker image (nginx + php-fpm + s6 with...| compose.yml — ePHPm + scheduler + queue sidecars, SQLite on a vo...| see README | tested 2026-10-12, v0.11.3-php8.5 |
| [suitecrm](apps/suitecrm/) | SuiteCRM 7.15.2 (SUITECRM_VERSION build arg) | Apache + mod_php (the usual SuiteCRM 7 host, e.g. the bitnami imag...| compose.yml — ePHPm + a cron service on the same image + MariaDB...| see README | tested 2026-10-12, v0.11.3-php8.4 |
| [tinyfilemanager](apps/tinyfilemanager/) | Tiny File Manager 2.6 (TFM_VERSION build arg) | the tinyfilemanager/tinyfilemanager image (php -S, PHP's developme...| compose.yml — ePHPm only (no database) | see README | tested 2026-10-12, v0.11.3-php8.5 |
| [typecho](apps/typecho/) | Typecho 1.3.0 (TYPECHO_VERSION build arg) | nginx + php-fpm (the joyqi/typecho images) | compose.yml — ePHPm + MariaDB 11 | see README | tested 2026-10-12, v0.11.3-php8.5 |
| [uvdesk](apps/uvdesk/) | UVdesk Community v1.1.8 (uvdesk/community-skeleton, UVDESK_VE | the official community-skeleton image (Ubuntu + apache2 + mod_php,...| compose.yml — ePHPm + MariaDB 11 | see README | tested 2026-10-12, v0.11.3-php8.3 |
| [yii2](apps/yii2/) | Yii 2 basic application template yiisoft/yii2-app-basic  | Apache + mod_php (the yiisoftware/yii2-php apache image), or nginx...| compose.yml — ePHPm + MariaDB 11 | see README | tested 2026-10-12, v0.11.3-php8.5 |
| [phpbb](apps/phpbb/) | phpBB | see README | MariaDB | see README | **untested** — test.sh is not reproducible on 2026-10-12: the login POST is answered 200 with the login form (form token rejected) in 4 of 5 runs; it passed once, earlier results unconfirmed |
| [filament-demo](apps/filament-demo/) | filament-demo | see README | see README | — | **blocked** — ePHPm's GD has no JPEG support: the demo seeder attaches JPEG images to every product and Spatie Media Library's `thumb` conversion fails (`imagecreatefro |
| [lychee](apps/lychee/) | lychee | see README | see README | — | **blocked** — ePHPm's GD has no WebP (or JPEG) support (`issues/koel.md`): Lychee writes every size variant (thumbnails, small, medium) as WebP, so an upload stores the |
| [opencart](apps/opencart/) | opencart | see README | see README | — | **blocked** — ePHPm's GD has no JPEG support: the CLI installer completes and the admin login page answers, but the storefront home page renders `Error: Call to undefin |
| [prestashop](apps/prestashop/) | prestashop | see README | see README | — | **blocked** — ePHPm's GD has no JPEG support: the installer's theme step calls `imagecreatefromjpeg()` (resizing the bundled language flag images) and aborts with `Call |
| [hortusfox](apps/hortusfox/) | hortusfox | see README | see README | — | blocked — every photo HortusFox stores (plants, plant gallery, locations, inventory) goes through a thumbnail step that calls `imagecreatefromjpeg()`/`imagejpeg()` for  |
| [pico](apps/pico/) | pico | see README | see README | — | blocked — upstream is end-of-life (README notice, March 2025; last release 2.1.4 from 2020) and it requires Twig 1.x, every release of which carries security advisories |
| [bludit](apps/bludit/) | Bludit 3.22.0 | Apache + mod_php / nginx + php-fpm | flat-file | yes (native) | tested 2026-10-12, v0.11.3-php8.5 |
| [postfixadmin](apps/postfixadmin/) | PostfixAdmin 4.0.5 | Apache/nginx + php-fpm in front of PostfixAdmin | MariaDB | no (not tried) | tested 2026-10-12, v0.11.3-php8.5 |
| [phpsysinfo](apps/phpsysinfo/) | phpSysInfo 3.4.7 | Apache/nginx + PHP | none | yes (native) | tested 2026-10-12, v0.11.3-php8.5 |
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
