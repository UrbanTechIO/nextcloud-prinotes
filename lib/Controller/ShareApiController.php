<?php

declare(strict_types=1);

namespace OCA\PriNotes\Controller;

use OCA\PriNotes\Service\NoteService;
use OCA\PriNotes\Service\ShareService;
use OCP\AppFramework\Http;
use OCP\AppFramework\Http\DataResponse;
use OCP\AppFramework\Http\TemplateResponse;
use OCP\AppFramework\OCS\OCSNotFoundException;
use OCP\AppFramework\OCSController;
use OCP\AppFramework\Db\DoesNotExistException;
use OCP\IRequest;

class ShareApiController extends OCSController {
    public function __construct(
        string $appName,
        IRequest $request,
        private ShareService $shareService,
        private NoteService  $noteService,
        private ?string $userId,
    ) {
        parent::__construct($appName, $request);
    }

    /** @NoAdminRequired @NoCSRFRequired */
    public function index(int $noteId): DataResponse {
        try {
            return new DataResponse($this->shareService->getSharesForNote($noteId, $this->userId));
        } catch (DoesNotExistException) {
            throw new OCSNotFoundException('Note not found');
        }
    }

    /** @NoAdminRequired @NoCSRFRequired */
    public function create(int $noteId): DataResponse {
        $data = $this->request->getParams();
        unset($data['_route']);
        try {
            return new DataResponse($this->shareService->createShare($noteId, $this->userId, $data), 201);
        } catch (DoesNotExistException) {
            throw new OCSNotFoundException('Note not found');
        }
    }

    /** @NoAdminRequired @NoCSRFRequired */
    public function destroy(int $noteId, int $shareId): DataResponse {
        try {
            $this->shareService->deleteShare($noteId, $shareId, $this->userId);
            return new DataResponse(['status' => 'ok']);
        } catch (DoesNotExistException) {
            throw new OCSNotFoundException('Share not found');
        }
    }

    /**
     * Public share view — no auth required
     * @NoAdminRequired
     * @NoCSRFRequired
     * @PublicPage
     */
    public function view(string $token): DataResponse {
        $share = $this->shareService->getByToken($token);
        if ($share === null) {
            throw new OCSNotFoundException('Share not found');
        }
        try {
            $note = $this->noteService->get($share->getNoteId(), $share->getOwnerId());
            // Strip lock info from public view
            unset($note['lockPinHash'], $note['isLocked']);
            return new DataResponse([
                'note'        => $note,
                'permissions' => $share->getPermissions(),
            ]);
        } catch (DoesNotExistException) {
            throw new OCSNotFoundException('Note not found');
        }
    }
}
