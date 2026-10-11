# Pico on ePHPm

| | |
|---|---|
| App | [Pico](https://picocms.org) 2.1.4 (`picocms/pico-composer`) |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | Apache (`.htaccess`) / nginx + php-fpm |
| Default stack | none shipped |
| Single container | — |
| Status | blocked — upstream is end-of-life (README notice, March 2025; last release 2.1.4 from 2020) and it requires Twig 1.x, every release of which carries security advisories that make Composer refuse the install; no recipe is shipped. Probed 2026-10-11 on v0.11.3-php8.5 with the advisories overridden: the sample site renders, with 33 PHP 8.5 deprecation notices from those libraries |

## Why there is no recipe

* **Pico is end-of-life.** The project's README carries an end-of-life
  notice (March 2025); the last release is 2.1.4 (August 2020) and 3.0
  never left alpha (December 2020).
* **Its dependency set is unmaintained.** `picocms/pico` 2.1 requires
  `twig/twig ^1.36` and `symfony/yaml ^2.8`. Every Twig 1.x release is
  covered by security advisories, and current Composer refuses the install:
  `composer create-project picocms/pico-composer` fails with
  "twig/twig[v1.36.0, ..., v1.44.8] … not loaded, because they are affected
  by security advisories". It also needs
  `allow-plugins.picocms/composer-installer`, which predates Composer's
  plugin allow-list.
* **What the probe showed:** with `--no-security-blocking` and the plugin
  allowed, Pico 2.1.4 runs on ePHPm unchanged (document root `/`,
  `fallback = ["$uri", "$uri/", "/index.php?$query_string"]`) and serves its
  sample site with 200 — nothing about ePHPm stands in the way. The page
  carries 33 `Deprecated:` notices (`trim(): Passing null …` in
  symfony/yaml 2.8, Twig 1.x) because these libraries predate PHP 8.x; with
  `display_errors` off they would only reach the log.

Publishing a recipe would mean telling people to disable Composer's
security blocking for an unmaintained CMS, so this directory only records
the result. A maintained flat-file CMS with the same model is
[Grav](../grav/) (tested on ePHPm).
