# UVdesk Community Helpdesk on ePHPm

| | |
|---|---|
| App | [UVdesk Community](https://www.uvdesk.com) v1.1.8 (`uvdesk/community-skeleton`, `UVDESK_VERSION` build arg) — Symfony 5.4 |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.3` (Symfony 5.4's last tested PHP; the official image runs PHP 8.1) |
| Replaces | the official community-skeleton image (Ubuntu + apache2 + mod_php, with a MySQL server inside the same container) |
| Default stack | `compose.yml` — ePHPm + MariaDB 11 |
| Single container | not offered — UVdesk is MySQL/MariaDB only and builds its schema with Doctrine's MySQL DDL (same class of gap as [issues/shlink.md](../../issues/shlink.md)); not attempted |
| Status | tested 2026-10-11 on v0.11.3-php8.3 (`compose.yml`): image build (`composer create-project` with Flex), schema + default data + super admin by the entrypoint, support-centre front page, agent login through the member login form, a ticket created through the "Create ticket" form and read back from the ticket list and the ticket page, `about` on the console |

## What changes versus the official image

* **One process serves the helpdesk.** ePHPm is the HTTP server and the PHP
  runtime; `public/.htaccess` (everything that is not a file goes to
  `index.php`) is `[server] fallback` in `ephpm.toml`. MariaDB runs as its
  own service instead of inside the app container.
* **Built like the official image.** `composer create-project
  uvdesk/community-skeleton` in a `composer:2` stage: Symfony Flex resolves
  the skeleton's `flex-require` list and applies the recipes (the build
  needs `api.github.com` for the Flex recipe index).
* **No setup wizard.** The official image sends you through the web
  wizard, which writes `DATABASE_URL` into `.env`, runs
  `uvdesk_wizard:database:migrate` (schema + default data) and creates the
  super admin. Here `DATABASE_URL` and `APP_SECRET` come from the
  environment and the entrypoint runs the same two console commands on the
  first start (`uvdesk_wizard:database:migrate` in the `dev` environment —
  its fixtures loader is only registered there, which is the skeleton's
  default `APP_ENV`; the server itself runs `prod`), plus
  `uvdesk_wizard:defaults:create-user ROLE_SUPER_ADMIN` from
  `UVDESK_ADMIN_EMAIL` / `UVDESK_ADMIN_PASSWORD`. The site URL the wizard
  writes into `config/packages/uvdesk.yaml` comes from `UVDESK_SITE_URL`.
* **The console runs on the embedded PHP** through the `uvdesk` wrapper
  (`ephpm php bin/console`, deprecation notices muted).

## Run

```bash
UVDESK_ADMIN_EMAIL=you@example.com UVDESK_ADMIN_PASSWORD=change-me APP_SECRET=$(openssl rand -hex 16) \
  docker compose up -d
open http://localhost:8080/en/member/login     # agents
open http://localhost:8080/en/                 # the customer support centre
```

`UVDESK_SITE_URL` (default `http://localhost:8080`) is the address used in
e-mailed links. Set your own `APP_SECRET`; the compose default is a
placeholder.

```bash
docker compose exec ephpm uvdesk uvdesk_wizard:defaults:create-user ROLE_AGENT   # another user (interactive)
docker compose exec ephpm uvdesk debug:router
```

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | `composer create-project` of the skeleton onto the `ephpm/ephpm` image |
| `ephpm.toml` | Server config (docroot, fallback, blocked paths, upload limits) |
| `entrypoint.sh` | Seeds the assets volume, waits for the DB, creates schema + default data + super admin once, starts `ephpm serve` |
| `uvdesk` | `bin/console` wrapper over the embedded PHP |
| `compose.yml` | ePHPm + MariaDB |
| `test.sh` | The smoke test CI runs (`bash apps/uvdesk/test.sh`) |

## Configuration notes

* `public/assets` (ticket attachments, avatars, helpdesk logo) is a volume;
  PHP is never executed from it (`blocked_paths`).
* Upload limits follow UVdesk's own `uvdesk.yaml` (`max_post_size` 8 MiB,
  `upload_max_filesize` 2 MiB).
* Outgoing mail: `MAILER_URL` / `MAILER_DSN` are null transports in
  `compose.yml`; configure a real SMTP transport in the admin settings
  for notifications.
* Behind a TLS-terminating proxy set `UVDESK_SITE_URL` to the public URL
  and `[server.security] trusted_proxies` in
  `ephpm.toml`.
* OPcache runs with timestamp validation off (ePHPm's `serve` default).
  After changing PHP or YAML files run
  `docker compose exec ephpm ephpm cache reset` or restart the container.

## Known limitations

* **No inbound e-mail.** The mailbox component (turning e-mails into
  tickets) needs `ext-imap` and `ext-mailparse`, which the official image
  installs and the ePHPm build does not have. Tickets created on the web
  and through the API work.
* Symfony 5.4 on PHP 8.3 emits a stream of deprecation notices; they are
  filtered out (`error_reporting` in `ephpm.toml` and the `uvdesk`
  wrapper).
* `ext-gd` without JPEG/WebP (`issues/koel.md`): resizing uploaded JPEG
  avatars/logos will not work. Not exercised.
