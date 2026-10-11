# Koel on ePHPm

| | |
|---|---|
| App | [Koel](https://koel.dev) v9.15.0 (`KOEL_VERSION` build arg) — Laravel 13, PHP ≥ 8.3 |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | the `phanan/koel` image (Apache + mod_php + cron + ffmpeg) |
| Default stack | `compose.yml` — ePHPm + scheduler sidecar + MariaDB 11 |
| Single container | not offered |
| Status | blocked — ePHPm's GD build has no JPEG/WebP/AVIF support, and `koel:init` (which the official image runs on every start) throws `No supported image format found.` before migrating. The image builds; nothing else was exercised. See `issues/koel.md`. |

## What this recipe does (once ePHPm's GD can encode JPEG or WebP)

* **One process serves the app.** ePHPm is the HTTP server and the PHP
  runtime; audio is streamed through PHP (`STREAMING_METHOD=php` — there is
  no X-Sendfile/X-Accel module).
* **The release tarball is used as-is.** Koel's GitHub release ships
  `vendor/` and the built front-end (`public/build`), exactly what the
  official image unpacks, so there is no Composer or Node stage.
* **`koel:init --no-assets --no-interaction --no-scheduler` on every start**,
  as the official `koel-init` does: generates `APP_KEY` on first run (into
  `storage/.env`, which `/app/.env` points at), migrates, creates the
  `admin@koel.dev` / `KoelIsCool` account, links storage. Koel's daily jobs
  (`koel:scan`, `koel:prune`, podcast sync, clean-ups) run from the
  `scheduler` service instead of a crontab.
* **Same environment variables as Koel's `.env`**: `APP_URL`, `DB_*`,
  `MEDIA_PATH` (`/music`, the `music` volume), `STREAMING_METHOD`,
  `CACHE_DRIVER`, `SESSION_DRIVER`, `REDIS_*`, `LASTFM_*`, `SPOTIFY_*`, …

## Run

Not until the blocker above is fixed. Then:

```bash
docker compose up -d           # or: podman compose up -d
open http://localhost:8080     # EPHPM_PORT=8090 docker compose up -d to change
```

`bash apps/koel/test.sh` logs in through `POST /api/me`, creates a playlist
through `POST /api/playlists`, lists it, and runs `artisan koel:scan`.

## Known limitations

* **Blocked:** no JPEG/WebP/AVIF in ePHPm's GD (`issues/koel.md`).
* No `ffmpeg` in the image: no FLAC transcoding, no waveform/duration for
  formats getID3 cannot read. Build it in (`apt-get install ffmpeg`, then
  `FFMPEG_PATH=/usr/bin/ffmpeg`) if you need it.
* Streaming goes through PHP (`STREAMING_METHOD=php`); each stream holds a
  PHP execution slot for its duration.
