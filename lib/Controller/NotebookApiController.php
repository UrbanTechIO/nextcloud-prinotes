<?php

declare(strict_types=1);

namespace OCA\PriNotes\Controller;

use OCA\PriNotes\Service\NotebookService;
use OCP\AppFramework\Http\DataResponse;
use OCP\AppFramework\OCS\OCSNotFoundException;
use OCP\AppFramework\OCSController;
use OCP\AppFramework\Db\DoesNotExistException;
use OCP\IRequest;

class NotebookApiController extends OCSController {
    public function __construct(
        string $appName,
        IRequest $request,
        private NotebookService $notebookService,
        private ?string $userId,
    ) {
        parent::__construct($appName, $request);
    }

    /** @NoAdminRequired @NoCSRFRequired */
    public function index(): DataResponse {
        return new DataResponse($this->notebookService->getAll($this->userId));
    }

    /** @NoAdminRequired @NoCSRFRequired */
    public function show(int $id): DataResponse {
        try {
            return new DataResponse($this->notebookService->get($id, $this->userId));
        } catch (DoesNotExistException) {
            throw new OCSNotFoundException('Notebook not found');
        }
    }

    /** @NoAdminRequired @NoCSRFRequired */
    public function create(): DataResponse {
        $data = $this->request->getParams();
        unset($data['_route']);
        return new DataResponse($this->notebookService->create($this->userId, $data), 201);
    }

    /** @NoAdminRequired @NoCSRFRequired */
    public function update(int $id): DataResponse {
        $data = $this->request->getParams();
        unset($data['_route']);
        try {
            return new DataResponse($this->notebookService->update($id, $this->userId, $data));
        } catch (DoesNotExistException) {
            throw new OCSNotFoundException('Notebook not found');
        }
    }

    /** @NoAdminRequired @NoCSRFRequired */
    public function destroy(int $id): DataResponse {
        try {
            $this->notebookService->delete($id, $this->userId);
            return new DataResponse(['status' => 'ok']);
        } catch (DoesNotExistException) {
            throw new OCSNotFoundException('Notebook not found');
        }
    }
}
