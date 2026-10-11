# LibreSpeed: per-request mode buffers the whole response; `flush()` does not stream

**Recipe:** `apps/librespeed` — **ePHPm:** `ephpm/ephpm:v0.11.3-php8.5` — **Date:** 2026-10-11

## Symptom

LibreSpeed's download test is `backend/garbage.php?ckSize=N`, which writes
N × 1 MiB of random bytes, calling `flush()` after each MiB, so that the
browser sees the bytes arrive and measures throughput as they do. On ePHPm
nothing reaches the client until the script has finished, and the whole body
is held in memory first:

| request | time to first byte | total | container RSS during the request |
|---|---|---|---|
| `garbage.php?ckSize=4` | 0.016 s | 0.04 s | — |
| `garbage.php?ckSize=100` (the client's default) | 0.26 s | 0.81 s | ~290 MB after |
| `garbage.php?ckSize=1024` (upstream's server-side maximum) | 1.9 s | 6.6 s | 2.3 GB |

(loopback, podman on Windows, one request at a time.) The speed test still
completes, but each of the client's 6 parallel download streams makes the
server buffer 100 MiB, and any client can make one request buffer 1 GiB
(×2 while the buffer doubles) — outside PHP's `memory_limit`, so the limit
does not stop it. With `[php] concurrency` workers that is a cheap memory
exhaustion for anything that streams large output (downloads generated in
PHP, exports, `readfile()` of big files, SSE).

## Minimal repro

```php
<?php // big.php
$chunk = str_repeat('x', 1048576);
for ($i = 0; $i < 512; $i++) { echo $chunk; flush(); }
```

`curl -o /dev/null -w '%{time_starttransfer}\n' http://127.0.0.1:8080/big.php`
— the first byte arrives only after all 512 MiB have been produced, and the
process grows by >512 MiB while it runs. Under php-fpm/Apache the first byte
arrives immediately and memory stays flat.

## Suspected cause

`crates/ephpm-php/ephpm_wrapper.c`: `ephpm_sapi_ub_write()` appends every
write to a `realloc`-grown `output_buf` (doubling), and `ephpm_sapi_flush()`
is a deliberate no-op ("we buffer the entire response and send it at once").
The Rust side reads the finished buffer with `ephpm_get_output_buf()`
(`crates/ephpm-php/src/lib.rs`). Streaming exists only for worker mode
(`send_response_stream` in `worker_bridge.rs`). Per-request mode would need
`flush` (and/or `ub_write` past a threshold) to hand chunks to a channel the
hyper body reads from, after headers are committed — and, independently, a
cap on `output_buf` so a single response cannot grow without bound.

## Workaround in the recipe

`entrypoint.sh` points the clients at 10 MiB chunks (`DL_CHUNK_MB`, written
into `settings.json` and `index-classic.html`) and caps `garbage.php` at
32 MiB per request (`GARBAGE_MAX_MB`) instead of 1024. Download results are
plausible but the measurement includes the buffering delay at the start of
each chunk.
