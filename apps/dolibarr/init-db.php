<?php
/**
 * Load Dolibarr's schema and default data into an empty MySQL/MariaDB
 * database — the official dolibarr/dolibarr image's initializeDatabase()
 * (docker-run.sh), which pipes the same files through the `mysql` client,
 * done over mysqli so the image needs no client binaries.
 *
 * Same order and the same edits as the official script: tables, then keys,
 * then functions, then data (minus the per-country accounting charts),
 * comments stripped and __ENTITY__ replaced by 1. A failing statement is
 * reported and loading goes on (see load()). Some failures are expected —
 * the key files say so themselves ("Duplicate key name 'uk_code_region'
 * ... to ignore").
 *
 * Usage: ephpm php init-db.php <htdocs dir>   (DOLI_DB_* from the environment)
 */

declare(strict_types=1);

$htdocs = rtrim($argv[1] ?? '/var/www/dolibarr/htdocs', '/');
$sqlDir = $htdocs . '/install/mysql';

mysqli_report(MYSQLI_REPORT_OFF);
$db = mysqli_connect(
    getenv('DOLI_DB_HOST') ?: 'db',
    getenv('DOLI_DB_USER') ?: 'dolibarr',
    getenv('DOLI_DB_PASSWORD') ?: '',
    getenv('DOLI_DB_NAME') ?: 'dolibarr',
    (int) (getenv('DOLI_DB_HOST_PORT') ?: 3306),
);
if (!$db) {
    fwrite(STDERR, 'cannot connect: ' . mysqli_connect_error() . PHP_EOL);
    exit(1);
}
mysqli_set_charset($db, 'utf8mb4');

/**
 * Split an SQL file into statements: `;` ends a statement unless it is
 * inside a quoted string, and `--` / `#` comments run to the end of the
 * line (Dolibarr's table files carry trailing comments, some with `;`).
 */
function statements(string $sql): array
{
    $out = [];
    $buf = '';
    $quote = null;
    $len = strlen($sql);
    for ($i = 0; $i < $len; $i++) {
        $c = $sql[$i];
        if ($quote !== null) {
            $buf .= $c;
            if ($c === '\\' && $i + 1 < $len) {
                $buf .= $sql[++$i];
            } elseif ($c === $quote) {
                $quote = null;
            }
            continue;
        }
        // (any `--` outside a string, as the official image's `sed 's/--.*//'`
        // treats it — Dolibarr's files also write `--comment` without a space)
        if (($c === '-' && substr($sql, $i, 2) === '--') || $c === '#') {
            $eol = strpos($sql, "\n", $i);
            $i = $eol === false ? $len : $eol - 1;
            continue;
        }
        if ($c === "'" || $c === '"' || $c === '`') {
            $quote = $c;
        } elseif ($c === ';') {
            if (trim($buf) !== '') {
                $out[] = trim($buf);
            }
            $buf = '';
            continue;
        }
        $buf .= $c;
    }
    if (trim($buf) !== '') {
        $out[] = trim($buf);
    }
    return $out;
}

/**
 * Run every statement of a file; a failing statement is reported and the
 * rest of the file still runs — what Dolibarr's own web installer (step2)
 * does. (`mysql < file` in the official image would stop the file there;
 * llx_10_c_regions.sql, for instance, carries a duplicate region code, and
 * stopping at it would leave the regions and departments half-loaded.)
 */
function load(mysqli $db, string $file, bool $entity = false): int
{
    $sql = file_get_contents($file);
    if ($entity) {
        $sql = str_replace('__ENTITY__', '1', $sql);
    }
    $failed = 0;
    foreach (statements($sql) as $stmt) {
        if (!mysqli_query($db, $stmt)) {
            fwrite(STDERR, basename($file) . ': ' . mysqli_error($db) . PHP_EOL);
            $failed++;
        }
    }
    return $failed;
}

$failed = 0;
$tables = glob($sqlDir . '/tables/*.sql');
foreach ($tables as $f) {
    if (!str_ends_with($f, '.key.sql')) {
        $failed += load($db, $f);
    }
}
foreach ($tables as $f) {
    if (str_ends_with($f, '.key.sql')) {
        $failed += load($db, $f);
    }
}
foreach (glob($sqlDir . '/functions/*.sql') as $f) {
    $failed += load($db, $f);
}
foreach (glob($sqlDir . '/data/*.sql') as $f) {
    if (str_contains(basename($f), 'llx_accounting_account_')) {
        continue;
    }
    $failed += load($db, $f, true);
}

$version = getenv('DOLI_VERSION') ?: '';
foreach ([
    "DELETE FROM llx_const WHERE name IN ('MAIN_VERSION_LAST_INSTALL', 'MAIN_NOT_INSTALLED', 'MAIN_LANG_DEFAULT')",
    "INSERT INTO llx_const(name,value,type,visible,note,entity) VALUES ('MAIN_VERSION_LAST_INSTALL', '" . mysqli_real_escape_string($db, $version) . "', 'chaine', 0, 'Dolibarr version when install', 0)",
    "INSERT INTO llx_const(name,value,type,visible,note,entity) VALUES ('MAIN_LANG_DEFAULT', 'auto', 'chaine', 0, 'Default language', 1)",
] as $q) {
    if (!mysqli_query($db, $q)) {
        fwrite(STDERR, $q . ': ' . mysqli_error($db) . PHP_EOL);
        $failed++;
    }
}

// The first super admin (the official image stores an md5 hash, which
// Dolibarr accepts and re-hashes on the first login).
$login = getenv('DOLI_ADMIN_LOGIN') ?: 'admin';
$pass = getenv('DOLI_ADMIN_PASSWORD') ?: '';
if ($pass !== '') {
    $s = mysqli_prepare($db, "INSERT INTO llx_user (entity, login, pass_crypted, lastname, admin, statut) VALUES (0, ?, ?, 'SuperAdmin', 1, 1)");
    $hash = md5($pass);
    mysqli_stmt_bind_param($s, 'ss', $login, $hash);
    if (!mysqli_stmt_execute($s)) {
        fwrite(STDERR, 'admin user: ' . mysqli_error($db) . PHP_EOL);
        $failed++;
    }
}

// Like the official script, a failing file is reported and the load goes on.
echo $failed === 0 ? "schema and default data loaded\n" : "schema loaded; $failed file(s)/statement(s) failed (see above)\n";
exit(0);
