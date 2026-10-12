# ePHPm issues found while writing the FOSSBilling recipe

Found on `ephpm/ephpm:v0.11.3-php8.5` (PHP 8.5.7, zlib 1.3.2), 2026-10-12.

## zlib file streams read and write nothing (`gzopen`, `compress.zlib://`)

**Severity: high for apps that use Symfony Intl (FOSSBilling, and any app that
formats currencies/locales through it).** `gzdecode()`/`gzencode()` work, but
every file-based zlib stream is empty:

```php
file_put_contents('/tmp/a.gz', gzencode(str_repeat('hello ', 100)));
strlen(gzread(gzopen('/tmp/a.gz', 'r'), 1000));       // int(0), expected 600
strlen(file_get_contents('compress.zlib:///tmp/a.gz')); // int(0), expected 600
$g = gzopen('/tmp/b.gz', 'w'); gzwrite($g, 'abc'); gzclose($g);
filesize('/tmp/b.gz');                                  // int(0), expected 23
```

(`ephpm php -r`, same result under `ephpm serve`.) `fopen()` and `gzopen()`
succeed; reads return the empty string with `feof()` false.

`symfony/intl`'s `GzipStreamWrapper` loads its data tables
(`Resources/data/*.php.gz`) through `fopen('compress.zlib://...')`, so the
first `Currencies::exists()` / `Languages::getNames()` call dies with
`Failed opening required '.../currencies/en.php.gz'`. In FOSSBilling that is
the home page and admin login (HTTP 500 after a successful install).

## Same root cause seen through `ZipArchive` (MODX recipe, 2026-10-12)

`ZipArchive::extractTo()` of MODX 3.1.1's `core.transport.zip` (1957 entries)
fails part-way: `getFromIndex()` returns false for 1379 of 1725 files with
`getStatusString()` = `Zlib error: stream error`, while the other 346 read
fine. MODX's CLI installer then aborts with "could not unpack
core.transport.zip". `gzdecode()` on the same kind of data works, so the
breakage looks specific to zlib's streaming inflate (the path used by
`gzopen`, `compress.zlib://` and libzip) in the SDK build. Anything that
unpacks zips with deflate entries (installers, plugin/theme/package
managers, Composer-in-PHP) is likely affected.
