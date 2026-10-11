#!/usr/bin/env php
<?php
/**
 * plugin-loader.php <name> — prints a plugins-enabled/ stub that loads
 * plugins/<name>.php and instantiates the single class it defines (the
 * same job as the official image's plugin-loader.php). A plugin whose
 * constructor needs arguments cannot be enabled this way: write the stub
 * by hand, as the error message shows.
 */

declare(strict_types=1);

if (PHP_SAPI !== 'cli' || $argc !== 2) {
    fwrite(STDERR, "usage: plugin-loader.php <plugin-name>\n");
    exit(1);
}
$name = $argv[1];
if (basename($name) !== $name || !preg_match('/^[a-z0-9-]+$/', $name)) {
    fwrite(STDERR, "Refusing to load plugin \"$name\" (bad name).\n");
    exit(1);
}
$file = __DIR__ . "/plugins/$name.php";
if (!is_readable($file)) {
    fwrite(STDERR, "Unable to find plugin file plugins/$name.php.\n");
    exit(1);
}

// The class the plugin file defines (exactly one).
$classes = [];
$tokens = token_get_all((string) file_get_contents($file));
for ($i = 0, $n = count($tokens); $i < $n; $i++) {
    if (is_array($tokens[$i]) && $tokens[$i][0] === T_CLASS) {
        for ($j = $i + 1; $j < $n; $j++) {
            if (is_array($tokens[$j]) && $tokens[$j][0] === T_STRING) {
                $classes[] = $tokens[$j][1];
                break;
            }
        }
    }
}
if (count($classes) !== 1) {
    fwrite(STDERR, "Unable to load plugin \"$name\": it must define exactly one class.\n");
    exit(1);
}

// Adminer's bundled plugins are global classes extending Adminer\Plugin (or
// Adminer\Password etc.); provide stand-ins so the file loads outside Adminer.
foreach (['Plugin', 'Password', 'Adminer'] as $stub) {
    if (!class_exists("\\Adminer\\$stub")) {
        eval("namespace Adminer; class $stub {}");
    }
}
require $file;
$class = new ReflectionClass($classes[0]);
$ctor = $class->getConstructor();
if ($ctor !== null && $ctor->getNumberOfRequiredParameters() > 0) {
    $params = implode(', ', array_map(static fn ($p) => '$' . $p->getName(), $ctor->getParameters()));
    fwrite(STDERR, "Plugin \"$name\" needs constructor arguments ($params). Create plugins-enabled/$name.php yourself:\n"
        . "<?php require_once 'plugins/$name.php'; return new \\{$classes[0]}(/* arguments */);\n");
    exit(1);
}

echo "<?php\nrequire_once " . var_export("plugins/$name.php", true) . ";\n"
    . "return new \\{$classes[0]}();\n";
