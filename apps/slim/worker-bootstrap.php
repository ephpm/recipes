<?php

declare(strict_types=1);

/**
 * Worker-mode bootstrap for ePHPm's PSR-15 adapter (ephpm/psr15-worker).
 *
 * Builds the Slim-Skeleton application exactly as public/index.php does,
 * but RETURNS it instead of running it: the adapter calls
 * $app->handle($request) in a loop, one booted app per worker thread.
 * Pointed at by EPHPM_WORKER_BOOTSTRAP.
 */

use App\Application\Handlers\HttpErrorHandler;
use App\Application\Settings\SettingsInterface;
use DI\ContainerBuilder;
use Slim\Factory\AppFactory;

require __DIR__ . '/vendor/autoload.php';

$containerBuilder = new ContainerBuilder();

$settings = require __DIR__ . '/app/settings.php';
$settings($containerBuilder);

$dependencies = require __DIR__ . '/app/dependencies.php';
$dependencies($containerBuilder);

$repositories = require __DIR__ . '/app/repositories.php';
$repositories($containerBuilder);

$container = $containerBuilder->build();

AppFactory::setContainer($container);
$app = AppFactory::create();
$callableResolver = $app->getCallableResolver();

$middleware = require __DIR__ . '/app/middleware.php';
$middleware($app);

$routes = require __DIR__ . '/app/routes.php';
$routes($app);

/** @var SettingsInterface $settings */
$settings = $container->get(SettingsInterface::class);
$displayErrorDetails = $settings->get('displayErrorDetails');
$logError = $settings->get('logError');
$logErrorDetails = $settings->get('logErrorDetails');

$responseFactory = $app->getResponseFactory();
$errorHandler = new HttpErrorHandler($callableResolver, $responseFactory);

$app->addRoutingMiddleware();
$app->addBodyParsingMiddleware();
$errorMiddleware = $app->addErrorMiddleware($displayErrorDetails, $logError, $logErrorDetails);
$errorMiddleware->setDefaultErrorHandler($errorHandler);

return $app; // Slim\App implements Psr\Http\Server\RequestHandlerInterface
