<?php

declare(strict_types=1);

namespace OCA\PriNotes\Controller;

use OCA\PriNotes\Service\NoteService;
use OCA\PriNotes\Service\NotebookService;
use OCA\PriNotes\Service\TagService;
use OCA\PriNotes\Service\ReminderService;
use OCP\AppFramework\Http\DataResponse;
use OCP\AppFramework\OCSController;
use OCP\IRequest;

/**
 * Sync controller — used exclusively by the mobile app.
 * GET  /api/sync/pull?since=<unix_timestamp>   → all entities updated since timestamp
 * POST /api/sync/push                          → batch create/update/delete
 */
class SyncApiController extends OCSController {
    public function __construct(
        string $appName,
        IRequest $request,
        private NoteService     $noteService,
        private NotebookService $notebookService,
        private TagService      $tagService,
        private ReminderService $reminderService,
        private ?string         $userId,
    ) {
        parent::__construct($appName, $request);
    }

    /**
     * @NoAdminRequired
     * @NoCSRFRequired
     */
    public function pull(): DataResponse {
        $since = (int)($this->request->getParam('since', '0'));

        // Notes are critical — if these fail, let the exception propagate so the
        // mobile knows the pull failed and retries next sync without advancing lastSync.
        $notes      = $this->noteService->getUpdatedSince($this->userId, $since);
        $allNoteIds = $this->noteService->getAllIds($this->userId);

        // Non-critical data — a failure here must NOT block note sync.
        // Wrap each independently so one broken service never crashes the whole pull.
        $notebooks = [];
        try { $notebooks = $this->notebookService->getAll($this->userId); } catch (\Throwable $e) {}

        $tags = [];
        try { $tags = $this->tagService->getAll($this->userId); } catch (\Throwable $e) {}

        $reminders = [];
        try { $reminders = $this->reminderService->getAll($this->userId); } catch (\Throwable $e) {}

        return new DataResponse([
            'serverTime' => time(),
            'notes'      => $notes,
            'allNoteIds' => $allNoteIds,
            'notebooks'  => $notebooks,
            'tags'       => $tags,
            'reminders'  => $reminders,
        ]);
    }

    /**
     * @NoAdminRequired
     * @NoCSRFRequired
     */
    public function push(): DataResponse {
        $body = $this->request->getParams();
        unset($body['_route']);

        $results = [
            'notes'     => [],
            'notebooks' => [],
            'tags'      => [],
            'errors'    => [],
        ];

        // Process notebooks first (notes may reference them)
        foreach ($body['notebooks'] ?? [] as $nb) {
            try {
                if (!empty($nb['id']) && $nb['id'] > 0) {
                    $results['notebooks'][] = $this->notebookService->update((int)$nb['id'], $this->userId, $nb);
                } else {
                    $results['notebooks'][] = $this->notebookService->create($this->userId, $nb);
                }
            } catch (\Throwable $e) {
                $results['errors'][] = ['entity' => 'notebook', 'data' => $nb, 'error' => $e->getMessage()];
            }
        }

        // Process tags
        foreach ($body['tags'] ?? [] as $tag) {
            try {
                if (!empty($tag['id']) && $tag['id'] > 0) {
                    $results['tags'][] = $this->tagService->update((int)$tag['id'], $this->userId, $tag);
                } else {
                    $results['tags'][] = $this->tagService->create($this->userId, $tag);
                }
            } catch (\Throwable $e) {
                $results['errors'][] = ['entity' => 'tag', 'data' => $tag, 'error' => $e->getMessage()];
            }
        }

        // Process notes
        foreach ($body['notes'] ?? [] as $note) {
            try {
                if (!empty($note['id']) && $note['id'] > 0) {
                    $results['notes'][] = $this->noteService->update((int)$note['id'], $this->userId, $note);
                } else {
                    $results['notes'][] = $this->noteService->create($this->userId, $note);
                }
            } catch (\Throwable $e) {
                $results['errors'][] = ['entity' => 'note', 'data' => ['id' => $note['id'] ?? null], 'error' => $e->getMessage()];
            }
        }

        // Process permanent note deletions from mobile app
        foreach ($body['deletedNoteIds'] ?? [] as $id) {
            try {
                $this->noteService->delete((int)$id, $this->userId);
            } catch (\Throwable) {
                // already gone — ignore
            }
        }

        // Process tag deletions from mobile app
        foreach ($body['deletedTagIds'] ?? [] as $id) {
            try {
                $this->tagService->delete((int)$id, $this->userId);
            } catch (\Throwable) {
                // already gone — ignore
            }
        }

        $results['serverTime'] = time();
        return new DataResponse($results);
    }
}
