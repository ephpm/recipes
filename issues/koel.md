# Koel blocked: ePHPm's GD has no JPEG, WebP or AVIF support

**Recipe:** `apps/koel` — **ePHPm:** `ephpm/ephpm:v0.11.3-php8.5` (PHP 8.5.7) — **Date:** 2026-10-11

## What happened

Koel v9.15.0's installer (`artisan koel:init --no-assets --no-interaction
--no-scheduler`, the command the official image runs on every start) dies
before migrating:

```
RuntimeException  No supported image format found.
at app/Services/Image/ImageWriter.php:74
  App\Services\Image\ImageWriter::findSupportedFormat("gd")
```

`ImageWriter` (cover art, avatars) probes the GD driver for `avif`, `webp`
and `jpg`, in that order, and throws when none can be encoded. The container
restart-loops on `koel:init`, so the app never serves.

## Minimal repro

```
$ podman run --rm --entrypoint ephpm docker.io/ephpm/ephpm:v0.11.3-php8.5 php -r 'var_export(gd_info());'
array (
  'GD Version' => 'bundled (2.1.0 compatible)',
  'FreeType Support' => false,
  'GIF Read Support' => true,
  'GIF Create Support' => true,
  'JPEG Support' => false,
  'PNG Support' => true,
  'WBMP Support' => true,
  'XPM Support' => false,
  'XBM Support' => true,
  'WebP Support' => false,
  'BMP Support' => true,
  'AVIF Support' => false,
  ...
)
$ ... php -r 'var_dump(function_exists("imagecreatefromjpeg"), function_exists("imagewebp"));'
bool(false)
bool(false)
```

## Suspected cause

The php-sdk (static-php-cli) build enables `gd` without `libjpeg`,
`libwebp`, `libavif` or `freetype` — the bundled GD compiled with only its
built-in PNG/GIF/BMP/WBMP codecs. Every mainstream PHP image path assumes
at least JPEG: `imagecreatefromjpeg()` / `imagejpeg()` do not exist in this
build.

## Impact beyond Koel (not exhaustive)

- **Koel**: blocked outright (installer refuses to run).
- **BookStack**: image uploads go through intervention/image v3 on the GD
  driver; JPEG/WebP uploads cannot be decoded for thumbnails. Not exercised
  by its `test.sh` (which uploads no image); noted in its README.
- **Snipe-IT** (`IMAGE_LIB=gd`), **WordPress** (`wp_image_editor_gd`
  reports JPEG unsupported), **Firefly III** (attachment previews), and any
  app resizing avatars/thumbnails: JPEG/WebP handling fails or silently
  skips.

## Suggested fix

Build `gd` in the php-sdk with `--with-jpeg --with-webp --with-avif
--with-freetype` (static-php-cli: add `libjpeg`, `libwebp`, `libavif`,
`freetype` to the gd extension's libs). `ext-imagick` is a separate gap and
not needed for this.

## Outcome

`apps/koel` is committed with README status **blocked** and the recipe files
as written (untested beyond the image build and the `koel:init` failure).
