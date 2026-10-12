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
