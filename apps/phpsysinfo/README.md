# phpSysInfo 3.4.7 on ePHPm

| | |
|---|---|
| App | phpSysInfo 3.4.7 |
| ePHPm image | `ephpm/ephpm:v0.11.3-php8.5` |
| Replaces | Apache/nginx + PHP |
| Default stack | `compose.yml`: ePHPm alone (stateless, no database) |
| Single container | yes (native) |
| Status | tested 2026-10-12 on v0.11.3-php8.5: home page, XML and JSON data endpoints (Vitals and Memory sections populated from /proc), the ini file refused (403) |

## Notes

* Reports the container's own /proc by default; run with `pid: host` and the host's /proc mounted to report the host.
* `phpsysinfo.ini` is copied from the shipped `.new` file; it and `includes/` are in `blocked_paths`.
