<?php

declare(strict_types=1);

namespace OCA\PriNotes\Middleware;

use OCP\AppFramework\Http\DataResponse;
use OCP\AppFramework\Http;
use OCP\AppFramework\Middleware;

/**
 * Ensures all API responses include CORS headers for the mobile app.
 */
class ApiMiddleware extends Middleware {
    public function afterController($controller, $methodName, $response): \OCP\AppFramework\Http\Response {
        $response->addHeader('Access-Control-Allow-Origin', '*');
        $response->addHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
        $response->addHeader('Access-Control-Allow-Headers', 'Authorization, Content-Type, OCS-APIRequest');
        return $response;
    }
}
