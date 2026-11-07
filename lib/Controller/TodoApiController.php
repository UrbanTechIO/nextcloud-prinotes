<?php

declare(strict_types=1);

namespace OCA\PriNotes\Controller;

use InvalidArgumentException;
use OCA\PriNotes\Service\TodoService;
use OCP\AppFramework\Db\DoesNotExistException;
use OCP\AppFramework\Http\DataResponse;
use OCP\AppFramework\OCS\OCSBadRequestException;
use OCP\AppFramework\OCS\OCSNotFoundException;
use OCP\AppFramework\OCSController;
use OCP\IRequest;

class TodoApiController extends OCSController {
    public function __construct(
        string $appName,
        IRequest $request,
        private TodoService $service,
        private ?string $userId,
    ) {
        parent::__construct($appName, $request);
    }

    /** @NoAdminRequired @NoCSRFRequired */
    public function index(): DataResponse {
        return new DataResponse($this->service->getAll($this->userId));
    }

    /** @NoAdminRequired @NoCSRFRequired */
    public function create(): DataResponse {
        $data = $this->request->getParams();
        unset($data['_route']);
        try {
            return new DataResponse($this->service->create($this->userId, $data), 201);
        } catch (InvalidArgumentException $e) {
            throw new OCSBadRequestException($e->getMessage());
        }
    }

    /** @NoAdminRequired @NoCSRFRequired */
    public function update(int $id): DataResponse {
        $data = $this->request->getParams();
        unset($data['_route']);
        try {
            return new DataResponse($this->service->update($id, $this->userId, $data));
        } catch (DoesNotExistException) {
            throw new OCSNotFoundException('Task not found');
        } catch (InvalidArgumentException $e) {
            throw new OCSBadRequestException($e->getMessage());
        }
    }

    /** @NoAdminRequired @NoCSRFRequired */
    public function destroy(int $id): DataResponse {
        try {
            $this->service->delete($id, $this->userId);
            return new DataResponse(['status' => 'ok']);
        } catch (DoesNotExistException) {
            throw new OCSNotFoundException('Task not found');
        }
    }
}
