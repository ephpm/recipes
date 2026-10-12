# HortusFox on ePHPm

| | |
|---|---|
| App | [HortusFox](https://www.hortusfox.com) 6.3 |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | Apache + mod_php (the official `ghcr.io/danielbrendel/hortusfox-web` image) |
| Default stack | none shipped |
| Single container | — |
| Status | blocked — every photo HortusFox stores (plants, plant gallery, locations, inventory) goes through a thumbnail step that calls `imagecreatefromjpeg()`/`imagejpeg()` for JPEG uploads, and ePHPm's GD build has no JPEG support; no recipe is shipped (evaluated 2026-10-11, not run) |

## Why there is no recipe

HortusFox is a plant manager whose central workflow is photographing
plants. `UtilsModule::createThumbFile()` (used by `PlantsModel`,
`PlantPhotoModel`, `LocationsModel` and `InventoryModel`) resizes every
uploaded image with GD; the official image builds GD `--with-jpeg` for that
reason. On ePHPm v0.11.3 GD has PNG and GIF only, so a phone photo (JPEG)
upload ends in `Call to undefined function imagecreatefromjpeg()`. PNG and
GIF uploads would work, which is not a usable plant manager.

Everything else about the app fits ePHPm without changes: it is a small
Asatru framework app with a `public/` front controller (an Apache
`.htaccess` rewrite to `index.php`), MySQL/MariaDB through PDO, a
`cronjob` HTTP endpoint protected by `APP_CRON_PW`, and an install step
(`php asatru migrate:fresh` plus the admin user the entrypoint creates).
Once ePHPm's GD gains JPEG (the known SDK limit recorded for other
recipes), this becomes a straightforward MariaDB recipe.
