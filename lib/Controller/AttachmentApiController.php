<?php

declare(strict_types=1);

namespace OCA\PriNotes\Controller;

use OCA\PriNotes\Db\Attachment;
use OCA\PriNotes\Db\AttachmentMapper;
use OCP\AppFramework\Http;
use OCP\AppFramework\Http\DataResponse;
use OCP\AppFramework\Http\FileDisplayResponse;
use OCP\AppFramework\OCS\OCSNotFoundException;
use OCP\AppFramework\OCSController;
use OCP\AppFramework\Db\DoesNotExistException;
use OCP\Files\IRootFolder;
use OCP\IRequest;

class AttachmentApiController extends OCSController {
    public function __construct(
        string $appName,
        IRequest $request,
        private AttachmentMapper $attachmentMapper,
        private IRootFolder      $rootFolder,
        private ?string          $userId,
    ) {
        parent::__construct($appName, $request);
    }

    /**
     * @NoAdminRequired
     * @NoCSRFRequired
     */
    public function upload(): DataResponse {
        $file   = $this->request->getUploadedFile('file');
        $noteId = (int)$this->request->getParam('noteId', 0);

        if (empty($file) || $file['error'] !== UPLOAD_ERR_OK) {
            return new DataResponse(['error' => 'Upload failed'], Http::STATUS_BAD_REQUEST);
        }

        $allowedTypes = ['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/svg+xml', 'application/pdf'];
        if (!in_array($file['type'], $allowedTypes)) {
            return new DataResponse(['error' => 'File type not allowed'], Http::STATUS_BAD_REQUEST);
        }

        $maxSize = 20 * 1024 * 1024; // 20 MB
        if ($file['size'] > $maxSize) {
            return new DataResponse(['error' => 'File too large (max 20 MB)'], Http::STATUS_BAD_REQUEST);
        }

        // Store in user's Nextcloud folder: PriNotes/attachments/{noteId}/
        $userFolder = $this->rootFolder->getUserFolder($this->userId);
        $dir = 'PriNotes/attachments/' . $noteId;
        if (!$userFolder->nodeExists($dir)) {
            $userFolder->newFolder($dir);
        }

        $folder   = $userFolder->get($dir);
        $filename = $this->sanitizeFilename($file['name']);
        $nodeFile = $folder->newFile($filename, file_get_contents($file['tmp_name']));

        $att = new Attachment();
        $att->setNoteId($noteId);
        $att->setUserId($this->userId);
        $att->setFilename($filename);
        $att->setMimeType($file['type']);
        $att->setSize($file['size']);
        $att->setNcFileId($nodeFile->getId());
        $att->setCreatedAt(time());
        $att = $this->attachmentMapper->insert($att);

        return new DataResponse([
            'id'       => $att->getId(),
            'filename' => $att->getFilename(),
            'mimeType' => $att->getMimeType(),
            'size'     => $att->getSize(),
            'url'      => '/index.php/apps/prinotes/api/attachments/' . $att->getId(),
        ], 201);
    }

    /**
     * @NoAdminRequired
     * @NoCSRFRequired
     */
    public function show(int $id): Http\Response {
        try {
            $att = $this->attachmentMapper->findById($id, $this->userId);
            $userFolder = $this->rootFolder->getUserFolder($this->userId);
            $dir = 'PriNotes/attachments/' . $att->getNoteId();
            $file = $userFolder->get($dir . '/' . $att->getFilename());
            $response = new FileDisplayResponse($file);
            $response->addHeader('Content-Type', $att->getMimeType());
            $response->addHeader('Cache-Control', 'private, max-age=86400');
            return $response;
        } catch (DoesNotExistException) {
            throw new OCSNotFoundException('Attachment not found');
        }
    }

    /**
     * @NoAdminRequired
     * @NoCSRFRequired
     */
    public function destroy(int $id): DataResponse {
        try {
            $att = $this->attachmentMapper->findById($id, $this->userId);
            $userFolder = $this->rootFolder->getUserFolder($this->userId);
            $path = 'PriNotes/attachments/' . $att->getNoteId() . '/' . $att->getFilename();
            if ($userFolder->nodeExists($path)) {
                $userFolder->get($path)->delete();
            }
            $this->attachmentMapper->delete($att);
            return new DataResponse(['status' => 'ok']);
        } catch (DoesNotExistException) {
            throw new OCSNotFoundException('Attachment not found');
        }
    }

    private function sanitizeFilename(string $name): string {
        $name = preg_replace('/[^a-zA-Z0-9._\-]/', '_', $name);
        return substr($name, 0, 255);
    }
}
