<?php

declare(strict_types=1);

namespace OCA\PriNotes\Controller;

use OCA\PriNotes\Service\ReminderService;
use OCP\AppFramework\Http\DataResponse;
use OCP\AppFramework\OCS\OCSNotFoundException;
use OCP\AppFramework\OCSController;
use OCP\AppFramework\Db\DoesNotExistException;
use OCP\IRequest;

class ReminderApiController extends OCSController {
    public function __construct(
        string $appName,
        IRequest $request,
        private ReminderService $reminderService,
        private ?string $userId,
    ) {
        parent::__construct($appName, $request);
    }

    /** @NoAdminRequired @NoCSRFRequired */
    public function index(): DataResponse {
        return new DataResponse($this->reminderService->getAll($this->userId));
    }

    /** @NoAdminRequired @NoCSRFRequired */
    public function create(): DataResponse {
        $data = $this->request->getParams();
        unset($data['_route']);
        try {
            return new DataResponse($this->reminderService->create($this->userId, $data), 201);
        } catch (DoesNotExistException) {
            throw new OCSNotFoundException('Note not found');
        }
    }

    /** @NoAdminRequired @NoCSRFRequired */
    public function update(int $id): DataResponse {
        $data = $this->request->getParams();
        unset($data['_route']);
        try {
            return new DataResponse($this->reminderService->update($id, $this->userId, $data));
        } catch (DoesNotExistException) {
            throw new OCSNotFoundException('Reminder not found');
        }
    }

    /** @NoAdminRequired @NoCSRFRequired */
    public function destroy(int $id): DataResponse {
        try {
            $this->reminderService->delete($id, $this->userId);
            return new DataResponse(['status' => 'ok']);
        } catch (DoesNotExistException) {
            throw new OCSNotFoundException('Reminder not found');
        }
    }
}
