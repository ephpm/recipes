<?php
/**
 * WORKAROUND for ePHPm v0.11.3 (Linux): dns_get_record() never returns.
 *
 * ePHPm's Linux binary carries a resolver compat shim whose __res_nsearch()
 * tail-calls itself forever, so PHP's dns_get_record() / checkdnsrr() spin at
 * 100% CPU and never return (../../issues/freshrss.md has the repro). FreshRSS
 * resolves every feed host with dns_get_record() — for its SSRF protection
 * (internal-host check) and its per-host Retry-After bookkeeping — so without
 * this file every feed add and every refresh hangs a PHP thread for good.
 *
 * The recipe lists dns_get_record in disable_functions (PHP 8 then removes
 * the native function, which makes it redefinable) and loads this file as
 * auto_prepend_file, both for the server (ephpm.toml) and for the CLI (the
 * `php` shim). The replacement answers A lookups with gethostbynamel() and
 * AAAA lookups with glibc's `getent ahostsv6` — both go through getaddrinfo(),
 * which works — and that is all FreshRSS asks for. Other record types (MX,
 * TXT, …) are not supported and yield an empty result. Delete this file and
 * the two ini lines once ePHPm is fixed.
 */

declare(strict_types=1);

if (!function_exists('dns_get_record')) {
	/**
	 * @param mixed $authoritative_name_servers unused (always left as given)
	 * @param mixed $additional_records unused (always left as given)
	 * @return array<int,array<string,int|string>>|false
	 */
	function dns_get_record(string $hostname, int $type = DNS_ANY, &$authoritative_name_servers = null,
		&$additional_records = null, bool $raw = false): array|false {
		$hostname = rtrim($hostname, '.');
		if ($hostname === '') {
			return false;
		}
		$records = [];
		$record = static fn(string $name, string $key, string $address): array =>
			['host' => $hostname, 'class' => 'IN', 'ttl' => 0, 'type' => $name, $key => $address];

		if (($type & (DNS_A | DNS_ANY | DNS_ALL)) !== 0) {
			$ips = @gethostbynamel($hostname);
			if (is_array($ips)) {
				foreach (array_unique($ips) as $ip) {
					$records[] = $record('A', 'ip', $ip);
				}
			} elseif (($type & (DNS_AAAA | DNS_ANY | DNS_ALL)) === 0) {
				return false;
			}
		}

		if (($type & (DNS_AAAA | DNS_ANY | DNS_ALL)) !== 0 && function_exists('exec')
			&& preg_match('/^[A-Za-z0-9.-]{1,253}$/', $hostname) === 1) {
			$lines = [];
			@exec('getent ahostsv6 ' . escapeshellarg($hostname) . ' 2>/dev/null', $lines, $status);
			if ($status === 0) {
				$seen = [];
				foreach ($lines as $line) {
					$ip = strtok($line, " \t");
					// getent maps IPv4 answers as ::ffff:a.b.c.d — those are A records, already listed.
					if (is_string($ip) && !isset($seen[$ip]) && !str_starts_with($ip, '::ffff:')
						&& filter_var($ip, FILTER_VALIDATE_IP, FILTER_FLAG_IPV6) !== false) {
						$seen[$ip] = true;
						$records[] = $record('AAAA', 'ipv6', $ip);
					}
				}
			}
		}
		return $records;
	}
}
