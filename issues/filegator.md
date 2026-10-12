# `ZipArchive` cannot deflate or inflate: "Zlib error: stream error"

**Found with:** `apps/filegator` — **ePHPm:** `ephpm/ephpm:v0.11.3-php8.5`
(zip ext 1.22.8, libzip 1.11.4, zlib 1.3.2) — **Date:** 2026-10-11

## Symptom

FileGator's "Zip" action answers 500; its log has
`ZipArchive::close(): Zlib error: stream error`. Every `ZipArchive` operation
that goes through libzip's deflate codec fails, in both directions:

* writing: `close()` returns `false` for any entry stored with the default
  method (deflate); only `CM_STORE` entries can be written;
* reading: a deflated entry of an ordinary `.zip` (made by Windows'
  `Compress-Archive`) comes back as `false` / an empty stream, with the same
  status string.

PHP's own zlib extension is fine in the same process (`gzdeflate`,
`deflate_init(ZLIB_ENCODING_RAW)`, `compress.zlib://` all work), so pure-PHP
zip writers (ZipStream — Directory Lister's zip download works) are
unaffected. Anything that uses `ZipArchive` is: unzipping uploads in file
managers, plugin/theme/extension installers that prefer `ZipArchive`
(WordPress falls back to PclZip only when the class is missing), backup
exporters, XLSX/DOCX writers built on `ZipArchive` (PhpSpreadsheet,
PhpWord), Nextcloud/Matomo/... updaters.

## Minimal repro

```bash
podman run --rm --entrypoint ephpm docker.io/ephpm/ephpm:v0.11.3-php8.5 php -r '
  $z = new ZipArchive; $z->open("/tmp/a.zip", ZipArchive::CREATE);
  $z->addFromString("a.txt", "hello world");
  var_dump($z->close(), $z->getStatusString());'
# Warning: Zlib error: stream error ... bool(false)

podman run --rm --entrypoint ephpm docker.io/ephpm/ephpm:v0.11.3-php8.5 php -r '
  $z = new ZipArchive; $z->open("/tmp/b.zip", ZipArchive::CREATE);
  $z->addFromString("a.txt", "hello world");
  $z->setCompressionName("a.txt", ZipArchive::CM_STORE);
  var_dump($z->close());'
# bool(true)
```

It reproduces under `ephpm php`, so it is the PHP SDK build (or the final
link of the `ephpm` binary), not the SAPI.

## Suspected cause

`Z_STREAM_ERROR` from libzip's `deflateInit2()` / `inflateInit2()` while the
zlib extension's calls to the same functions succeed. The visible difference
is that ext/zlib installs its own `zalloc`/`zfree`, whereas libzip passes
`Z_NULL` and relies on the zlib implementation's default allocator. The
binary carries no stock zlib copyright string (`deflate 1.3.2 Copyright ...
Jean-loup Gailly`), so the zlib actually linked is not stock zlib — and the
Rust side links more than one deflate implementation (`flate2` with
`libz-sys` and `zlib-rs` in `Cargo.lock`). Worth checking which object
provides the `deflateInit2_`/`inflateInit2_` symbols in the final link and
whether that implementation rejects a `NULL` `zalloc`; adding a
`ZipArchive` deflate round trip to the php-sdk smoke tests would catch it.

## Workaround in the recipes

None possible from a recipe. `apps/filegator` documents that Zip/Unzip do
not work; its smoke test tries the Zip action and reports which way it went
(a fixed image is checked for a real zip archive).
