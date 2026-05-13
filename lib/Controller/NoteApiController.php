<?php

declare(strict_types=1);

namespace OCA\PriNotes\Controller;

use OCA\PriNotes\Service\NoteService;
use OCP\AppFramework\Http\DataResponse;
use OCP\AppFramework\Http\Response;
use OCP\AppFramework\OCS\OCSForbiddenException;
use OCP\AppFramework\OCS\OCSNotFoundException;
use OCP\AppFramework\OCSController;
use OCP\AppFramework\Db\DoesNotExistException;
use OCP\IRequest;

class NoteApiController extends OCSController {
    public function __construct(
        string $appName,
        IRequest $request,
        private NoteService $noteService,
        private ?string $userId,
    ) {
        parent::__construct($appName, $request);
    }

    /**
     * @NoAdminRequired
     * @NoCSRFRequired
     */
    public function index(): DataResponse {
        $notebookId = $this->request->getParam('notebookId') !== null
            ? (int)$this->request->getParam('notebookId') : null;
        $trashed  = filter_var($this->request->getParam('trashed', 'false'), FILTER_VALIDATE_BOOLEAN);
        $archived = filter_var($this->request->getParam('archived', 'false'), FILTER_VALIDATE_BOOLEAN);
        $tagId    = $this->request->getParam('tagId');

        if ($tagId !== null) {
            $notes = $this->noteService->getByTag($this->userId, (int)$tagId);
        } else {
            $notes = $this->noteService->getAll($this->userId, $notebookId, $trashed, $archived);
        }
        return new DataResponse($notes);
    }

    /**
     * @NoAdminRequired
     * @NoCSRFRequired
     */
    public function show(int $id): DataResponse {
        try {
            return new DataResponse($this->noteService->get($id, $this->userId));
        } catch (DoesNotExistException) {
            throw new OCSNotFoundException('Note not found');
        }
    }

    /**
     * @NoAdminRequired
     * @NoCSRFRequired
     */
    public function create(): DataResponse {
        $data = $this->request->getParams();
        unset($data['_route']);
        return new DataResponse($this->noteService->create($this->userId, $data), 201);
    }

    /**
     * @NoAdminRequired
     * @NoCSRFRequired
     */
    public function update(int $id): DataResponse {
        $data = $this->request->getParams();
        unset($data['_route']);
        try {
            return new DataResponse($this->noteService->update($id, $this->userId, $data));
        } catch (DoesNotExistException) {
            throw new OCSNotFoundException('Note not found');
        }
    }

    /**
     * @NoAdminRequired
     * @NoCSRFRequired
     */
    public function destroy(int $id): DataResponse {
        try {
            $forceDelete = filter_var($this->request->getParam('force', 'false'), FILTER_VALIDATE_BOOLEAN);
            if ($forceDelete) {
                $this->noteService->delete($id, $this->userId);
            } else {
                $this->noteService->trash($id, $this->userId);
            }
            return new DataResponse(['status' => 'ok']);
        } catch (DoesNotExistException) {
            throw new OCSNotFoundException('Note not found');
        }
    }

    /**
     * @NoAdminRequired
     * @NoCSRFRequired
     */
    public function restore(int $id): DataResponse {
        try {
            return new DataResponse($this->noteService->restore($id, $this->userId));
        } catch (DoesNotExistException) {
            throw new OCSNotFoundException('Note not found');
        }
    }

    /**
     * @NoAdminRequired
     * @NoCSRFRequired
     */
    public function versions(int $id): DataResponse {
        try {
            return new DataResponse($this->noteService->getVersions($id, $this->userId));
        } catch (DoesNotExistException) {
            throw new OCSNotFoundException('Note not found');
        }
    }

    /**
     * @NoAdminRequired
     * @NoCSRFRequired
     */
    public function restoreVersion(int $id, int $versionId): DataResponse {
        try {
            return new DataResponse($this->noteService->restoreVersion($id, $versionId, $this->userId));
        } catch (DoesNotExistException) {
            throw new OCSNotFoundException('Not found');
        }
    }

    /**
     * @NoAdminRequired
     * @NoCSRFRequired
     */
    public function deleteVersion(int $id, int $versionId): DataResponse {
        try {
            $this->noteService->deleteVersion($id, $versionId, $this->userId);
            return new DataResponse(['status' => 'ok']);
        } catch (DoesNotExistException) {
            throw new OCSNotFoundException('Not found');
        }
    }

    /**
     * @NoAdminRequired
     * @NoCSRFRequired
     */
    public function search(): DataResponse {
        $query = $this->request->getParam('q', '');
        if (strlen($query) < 2) {
            return new DataResponse([]);
        }
        return new DataResponse($this->noteService->search($this->userId, $query));
    }
}
