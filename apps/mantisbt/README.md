# MantisBT on ePHPm

| | |
|---|---|
| App | [MantisBT](https://mantisbt.org) 2.28.4 (`MANTIS_VERSION` build arg) |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | Apache + mod_php, or nginx + php-fpm |
| Default stack | `compose.yml`: ePHPm + MariaDB 11 |
| Single container | not offered (not tried on the embedded database) |
| Status | tested 2026-10-12 on v0.11.3-php8.5: unattended install on first start, log in as the configured administrator, create a project and category, report an issue through the web form and find it in the issue list, `php` CLI on the embedded PHP |

## Notes

* **Unattended install.** MantisBT's installer is a web page. On the first
  start the entrypoint serves it on a private loopback port, submits it once,
  and writes `config/config_inc.php` (in the `config` volume). Later starts
  run `admin/upgrade_unattended.php`.
* **Admin account.** The installer's `administrator` / `root` is renamed and
  re-passworded from `MANTIS_ADMIN_USER` / `MANTIS_ADMIN_PASSWORD` /
  `MANTIS_ADMIN_EMAIL`. Set `MANTIS_ADMIN_PASSWORD`, otherwise the password
  stays `root`.
* `admin/` is refused over HTTP by `blocked_paths` in `ephpm.toml`.
* **Config edits need a restart.** ePHPm serves with OPcache timestamp
  validation off, so after editing `config/config_inc.php` run
  `docker compose restart ephpm`.
* A fresh install has no project and no category: create them under Manage
  before reporting issues (an issue with no valid category answers 500).
* Mail: set `MANTIS_SMTP_HOST` (and `MANTIS_FROM_EMAIL`); there is no local
  sendmail in the image.

```bash
MANTIS_ADMIN_PASSWORD='something-long' docker compose up -d
```
