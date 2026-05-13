<?php

declare(strict_types=1);

namespace OCA\PriNotes\AppInfo;

use OCA\PriNotes\Middleware\ApiMiddleware;
use OCP\AppFramework\App;
use OCP\AppFramework\Bootstrap\IBootContext;
use OCP\AppFramework\Bootstrap\IBootstrap;
use OCP\AppFramework\Bootstrap\IRegistrationContext;

class Application extends App implements IBootstrap {
    public const APP_ID = 'prinotes';

    public function __construct(array $urlParams = []) {
        parent::__construct(self::APP_ID, $urlParams);
    }

    public function register(IRegistrationContext $context): void {
        $context->registerMiddleware(ApiMiddleware::class);
    }

    public function boot(IBootContext $context): void {
    }
}
