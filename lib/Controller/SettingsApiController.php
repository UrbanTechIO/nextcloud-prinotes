<?php

declare(strict_types=1);

namespace OCA\PriNotes\Controller;

use OCA\PriNotes\Service\SettingsService;
use OCP\AppFramework\Http\DataResponse;
use OCP\AppFramework\OCSController;
use OCP\IRequest;

class SettingsApiController extends OCSController {
    public function __construct(
        string $appName,
        IRequest $request,
        private SettingsService $settingsService,
        private ?string $userId,
    ) {
        parent::__construct($appName, $request);
    }

    /** @NoAdminRequired @NoCSRFRequired */
    public function get(): DataResponse {
        return new DataResponse($this->settingsService->getAll($this->userId));
    }

    /** @NoAdminRequired @NoCSRFRequired */
    public function set(): DataResponse {
        $data = json_decode($this->request->getBody(), true) ?? [];
        $this->settingsService->setMany($this->userId, $data);
        return new DataResponse($this->settingsService->getAll($this->userId));
    }
}
