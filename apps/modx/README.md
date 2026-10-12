# MODX Revolution on ePHPm

| | |
|---|---|
| App | MODX Revolution 3.1.1 (`MODX_VERSION` build arg) |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | Apache + mod_php / nginx + php-fpm |
| Default stack | `compose.yml`: ePHPm + MariaDB 11 |
| Status | **blocked** (checked 2026-10-12 on v0.11.3-php8.5): the CLI installer (`setup/index.php --installmode=new`) fails to unpack `core.transport.zip` (`ZipArchive` gives `Zlib error: stream error`); the home page then answers MODX's own 503. See the ZipArchive section of `issues/fossbilling.md`. |

The `ephpm.toml` (friendly URLs as `fallback = [..., "/index.php?q=$uri&$query_string"]`), the entrypoint that drives the CLI installer from the environment, and `compose.yml` are in place and will be re-tested once ePHPm's zlib streams are fixed. MODX 3.1.1 also logs many PHP 8.5 deprecation notices (non-canonical `(integer)` casts).
