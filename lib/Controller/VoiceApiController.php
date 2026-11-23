<?php

declare(strict_types=1);

namespace OCA\PriNotes\Controller;

use OCA\PriNotes\Service\VoiceFiles;
use OCP\AppFramework\Http;
use OCP\AppFramework\Http\DataResponse;
use OCP\AppFramework\Http\FileDisplayResponse;
use OCP\AppFramework\Controller;
use OCP\Files\Folder;
use OCP\Files\IRootFolder;
use OCP\Files\NotFoundException;
use OCP\IRequest;

/**
 * Voice recordings attached to notes. The files live in the user's own Nextcloud Files, in PriNotes/voice,
 * named by the id the apps give them; the note itself only keeps that id (and a label and length).
 */
/**
 * A plain controller (not OCS) on purpose: the apps need real HTTP status codes, such as 404 for a recording
 * that does not exist. OCS answers every request with HTTP 200 and puts the code in the body.
 */
class VoiceApiController extends Controller {
    private const DIR = 'PriNotes/voice';

    public function __construct(
        string $appName,
        IRequest $request,
        private IRootFolder $rootFolder,
        private ?string $userId,
    ) {
        parent::__construct($appName, $request);
    }

    /**
     * @NoAdminRequired
     * @NoCSRFRequired
     */
    public function upload(): DataResponse {
        $id   = (string)$this->request->getParam('id', '');
        $file = $this->request->getUploadedFile('file');

        if (!VoiceFiles::validId($id)) {
            return new DataResponse(['error' => 'Bad recording id'], Http::STATUS_BAD_REQUEST);
        }
        if (empty($file) || ($file['error'] ?? UPLOAD_ERR_NO_FILE) !== UPLOAD_ERR_OK) {
            return new DataResponse(['error' => 'Upload failed'], Http::STATUS_BAD_REQUEST);
        }
        $ext = VoiceFiles::extensionFor((string)($file['type'] ?? ''));
        if ($ext === null) {
            return new DataResponse(['error' => 'Not an audio type we keep'], Http::STATUS_BAD_REQUEST);
        }
        if (($file['size'] ?? 0) > VoiceFiles::MAX_BYTES) {
            return new DataResponse(['error' => 'Recording too large (max 50 MB)'], Http::STATUS_BAD_REQUEST);
        }

        $folder = $this->folder(true);
        // Uploading the same recording again (a retry after a dropped connection) replaces it.
        $this->removeAll($folder, $id);
        $folder->newFile($id . '.' . $ext, file_get_contents($file['tmp_name']));

        return new DataResponse(['id' => $id, 'mimeType' => VoiceFiles::mimeFor($ext), 'size' => (int)$file['size']], Http::STATUS_CREATED);
    }

    /**
     * @NoAdminRequired
     * @NoCSRFRequired
     */
    public function show(string $id): Http\Response {
        if (!VoiceFiles::validId($id)) {
            return new DataResponse(['error' => 'Not found'], Http::STATUS_NOT_FOUND);
        }
        $folder = $this->folder(false);
        if ($folder !== null) {
            foreach (VoiceFiles::extensions() as $ext) {
                if ($folder->nodeExists($id . '.' . $ext)) {
                    $response = new FileDisplayResponse($folder->get($id . '.' . $ext));
                    $response->addHeader('Content-Type', VoiceFiles::mimeFor($ext));
                    $response->addHeader('Cache-Control', 'private, max-age=86400');
                    return $response;
                }
            }
        }
        return new DataResponse(['error' => 'Not found'], Http::STATUS_NOT_FOUND);
    }

    /**
     * @NoAdminRequired
     * @NoCSRFRequired
     */
    public function destroy(string $id): DataResponse {
        if (!VoiceFiles::validId($id)) {
            return new DataResponse(['error' => 'Not found'], Http::STATUS_NOT_FOUND);
        }
        $folder = $this->folder(false);
        // Deleting what is already gone is fine: the apps retry deletes until they get an answer.
        if ($folder !== null) {
            $this->removeAll($folder, $id);
        }
        return new DataResponse(['status' => 'ok']);
    }

    private function folder(bool $create): ?Folder {
        $userFolder = $this->rootFolder->getUserFolder((string)$this->userId);
        if (!$userFolder->nodeExists(self::DIR)) {
            if (!$create) {
                return null;
            }
            $userFolder->newFolder(self::DIR);
        }
        $folder = $userFolder->get(self::DIR);
        return $folder instanceof Folder ? $folder : null;
    }

    private function removeAll(Folder $folder, string $id): void {
        foreach (VoiceFiles::extensions() as $ext) {
            try {
                if ($folder->nodeExists($id . '.' . $ext)) {
                    $folder->get($id . '.' . $ext)->delete();
                }
            } catch (NotFoundException) {
                // already gone
            }
        }
    }
}
