<?php

declare(strict_types=1);

namespace OCA\PriNotes\Controller;

use OCA\PriNotes\Service\TagService;
use OCP\AppFramework\Http\DataResponse;
use OCP\AppFramework\OCS\OCSNotFoundException;
use OCP\AppFramework\OCSController;
use OCP\AppFramework\Db\DoesNotExistException;
use OCP\IRequest;

class TagApiController extends OCSController {
    public function __construct(
        string $appName,
        IRequest $request,
        private TagService $tagService,
        private ?string $userId,
    ) {
        parent::__construct($appName, $request);
    }

    /** @NoAdminRequired @NoCSRFRequired */
    public function index(): DataResponse {
        return new DataResponse($this->tagService->getAll($this->userId));
    }

    /** @NoAdminRequired @NoCSRFRequired */
    public function create(): DataResponse {
        $data = $this->request->getParams();
        unset($data['_route']);
        return new DataResponse($this->tagService->create($this->userId, $data), 201);
    }

    /** @NoAdminRequired @NoCSRFRequired */
    public function update(int $id): DataResponse {
        $data = $this->request->getParams();
        unset($data['_route']);
        try {
            return new DataResponse($this->tagService->update($id, $this->userId, $data));
        } catch (DoesNotExistException) {
            throw new OCSNotFoundException('Tag not found');
        }
    }

    /** @NoAdminRequired @NoCSRFRequired */
    public function destroy(int $id): DataResponse {
        try {
            $this->tagService->delete($id, $this->userId);
            return new DataResponse(['status' => 'ok']);
        } catch (DoesNotExistException) {
            throw new OCSNotFoundException('Tag not found');
        }
    }
}
