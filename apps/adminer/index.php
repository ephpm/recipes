<?php
/**
 * Front controller for the ePHPm recipe — what the official adminer image's
 * index.php does: load the plugins enabled in plugins-enabled/, prefill the
 * "Server" field from ADMINER_DEFAULT_SERVER (default: the compose `db`
 * service), then run adminer.php.
 */

declare(strict_types=1);

namespace ephpm_recipe {
    function adminer_object(): \Adminer\Plugins
    {
        /** Prefills the "Server" login field with ADMINER_DEFAULT_SERVER. */
        final class DefaultServerPlugin extends \Adminer\Plugin
        {
            public function __construct(private \Adminer\Adminer $adminer)
            {
            }

            public function loginFormField(...$args): string
            {
                return (function (...$args): string {
                    $field = $this->loginFormField(...$args);
                    $server = \getenv('ADMINER_DEFAULT_SERVER') ?: 'db';
                    // Adminer 6 quotes attributes with ' (older versions with ") — accept both.
                    return \preg_replace_callback(
                        '/name=(["\'])auth\[server\]\1 value=\1\1/',
                        static fn (array $m): string => \sprintf('name=%1$sauth[server]%1$s value=%1$s%2$s%1$s', $m[1], \htmlspecialchars($server)),
                        $field,
                    );
                })->call($this->adminer, ...$args);
            }
        }

        $plugins = [];
        foreach (\glob(__DIR__ . '/plugins-enabled/*.php') ?: [] as $plugin) {
            $plugins[] = require $plugin;
        }
        $adminer = new \Adminer\Plugins($plugins);

        // Wrap whichever object answers loginFormField last (Adminer itself unless a plugin overrides it).
        (function (): void {
            $last = &$this->hooks['loginFormField'][\array_key_last($this->hooks['loginFormField'])];
            if ($last instanceof \Adminer\Adminer) {
                $plugin = new DefaultServerPlugin($last);
                $this->plugins[] = $plugin;
                $last = $plugin;
            }
        })->call($adminer);

        return $adminer;
    }
}

namespace {
    function adminer_object(): \Adminer\Plugins
    {
        return \ephpm_recipe\adminer_object();
    }

    require __DIR__ . '/adminer.php';
}
