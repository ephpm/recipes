# LibreSpeed on ePHPm

| | |
|---|---|
| App | [LibreSpeed](https://github.com/librespeed/speedtest) v6.3.0 (`LIBRESPEED_VERSION` build arg) |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | Apache + mod_php (the `ghcr.io/librespeed/speedtest` image) |
| Default stack | `compose.yml` — ePHPm + MariaDB 11 (results / telemetry database) |
| Single container | `compose.sqlite.yml` — results in LibreSpeed's own SQLite file (the official image's default; not experimental) |
| Status | tested 2026-10-11 on v0.11.3-php8.5 (MariaDB and SQLite): front end, download chunks from `garbage.php`, upload POST to `empty.php`, `getIP.php`, store a result through `results/telemetry.php` and read it back on the password-protected stats page |

## What changes versus the official image

* **One process.** ePHPm serves the HTML/JS front end and runs the backend
  endpoints (`backend/garbage.php`, `empty.php`, `getIP.php`) and the
  telemetry/stats pages. There are no rewrites to translate.
* **Same environment variables and modes.** `MODE` (`standalone`, `backend`,
  `frontend`, `dual`), `TITLE`, `TAGLINE`, `TELEMETRY`, `PASSWORD`,
  `DB_TYPE` (`sqlite` | `mysql` | `postgresql`), `DB_HOSTNAME`, `DB_PORT`,
  `DB_NAME`, `DB_USERNAME`, `DB_PASSWORD`, `ENABLE_ID_OBFUSCATION`,
  `OBFUSCATION_SALT`, `REDACT_IP_ADDRESSES`, `GDPR_EMAIL`,
  `SERVER_LIST_URL`, `IPINFO_APIKEY`, `USE_NEW_DESIGN`, and a mounted
  `/servers.json` — `entrypoint.sh` is the official one with Apache taken
  out. `WEBPORT` is not used (ePHPm listens on 8080; publish another host
  port with `EPHPM_PORT`).
* **The telemetry table is created for you** on MySQL/MariaDB and
  PostgreSQL (upstream ships `results/telemetry_*.sql` to load by hand).
* **Telemetry settings are read from the environment at runtime** instead
  of being `sed`-patched into `telemetry_settings.php`, so passwords with
  special characters work. A generated ID-obfuscation salt is kept in the
  `/database` volume, so obfuscated result links survive restarts.
* **Smaller download chunks — read this.** ePHPm (per-request mode)
  buffers a whole PHP response before sending it; `flush()` does not
  stream ([`issues/librespeed.md`](../../issues/librespeed.md)). LibreSpeed's
  download test asks `garbage.php` for 100 MiB per request, which ePHPm
  would hold in memory before the first byte goes out, and `garbage.php`
  accepts up to 1024 MiB from any client. The recipe therefore points the
  browsers at 10 MiB chunks (`DL_CHUNK_MB`) and caps a single response at
  32 MiB (`GARBAGE_MAX_MB`). Results are plausible, but on fast links the
  short pause before each chunk starts makes the download figure somewhat
  conservative compared with Apache.

## Run

```bash
docker compose up -d                       # or: podman compose up -d
open http://localhost:8080                 # EPHPM_PORT=8090 ... to change
open http://localhost:8080/results/stats.php   # log in with PASSWORD
```

Single container (SQLite results in the `database` volume):

```bash
docker compose -f compose.sqlite.yml up -d
```

No telemetry at all: set `TELEMETRY: "false"` and drop the `db` service.

```bash
docker compose exec ephpm ephpm php -r 'echo PHP_VERSION, "\n";'   # the embedded CLI
```

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Downloads the release, keeps what the official image copies into `/speedtest` |
| `ephpm.toml` | Server config: 32 MiB request bodies (upload test), compression off |
| `entrypoint.sh` | The official entrypoint without Apache: assembles the web root per `MODE`, telemetry settings, table creation, chunk-size cap |
| `compose.yml`, `compose.sqlite.yml` | The two stacks |
| `test.sh` | The smoke test CI runs (`bash apps/librespeed/test.sh`) |

## Configuration notes

* Behind a reverse proxy set `[server.security] trusted_proxies`; LibreSpeed
  itself reads `X-Forwarded-For` / `X-Real-IP` / `CF-Connecting-IP` for the
  client IP (as upstream).
* Response compression is off in `ephpm.toml`: compressing random bytes and
  tiny ping responses only costs CPU and skews the measurement.
* `DL_CHUNK_MB` and `GARBAGE_MAX_MB` can be raised if the server has the
  memory: each parallel download stream (6 per client by default) holds
  one chunk in memory while it is produced.

## Known limitations

* The results-sharing image (`results/index.php`, the PNG with the numbers)
  draws text with `imagefttext()`; ePHPm's GD has no FreeType, so that
  image does not render. The stats page and stored results are unaffected.
* Whole-response buffering (above) — not a correctness problem, but the
  download measurement is not byte-for-byte what Apache would give.
