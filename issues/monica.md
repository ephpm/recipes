# Monica blocked: ePHPm's GD has no FreeType support (`imagettfbbox()` missing)

**Recipe:** `apps/monica` — **ePHPm:** `ephpm/ephpm:v0.11.3-php8.3` (PHP 8.3) — **Date:** 2026-10-11

## What happened

Monica v4.1.2 installs and the first account registers fine (migrations,
Passport keys, login all work), but **creating a contact** — the app's core
action — answers 500:

```
local.ERROR: Call to undefined function Intervention\Image\Gd\imagettfbbox()
  at /app/vendor/intervention/image/src/Intervention/Image/Gd/Font.php:93
```

Every new contact gets a generated default avatar (initials on a coloured
disc — `App\Services\Contact\Avatar\GenerateDefaultAvatar`, registered
unconditionally in `AppServiceProvider`, through `laravolt/avatar` with
`vendor/laravolt/avatar/fonts/OpenSans-Bold.ttf`). Intervention/Image's GD
driver renders the text with `imagettfbbox()`/`imagettftext()`, which exist
only when GD is built with FreeType. There is no configuration switch to
turn the generated avatars off.

## Minimal repro

```
$ podman run --rm --entrypoint ephpm docker.io/ephpm/ephpm:v0.11.3-php8.3 php -r \
    'var_dump(gd_info()["FreeType Support"], function_exists("imagettfbbox"));'
bool(false)
bool(false)
```

## Cause and fix

Same root cause as `issues/koel.md`: the php-sdk builds `gd` with only its
bundled codecs — no `libjpeg`, `libwebp`, `libavif` and no `freetype`. Add
`freetype` (with `--with-freetype`) alongside the image codecs to the gd
extension's libraries in the php-sdk build.

## Outcome

`apps/monica` is committed with README status **blocked** and the recipe
files as written (image build, migrations, registration and login were
exercised; contact creation fails on the missing font support).
