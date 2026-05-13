<?php

declare(strict_types=1);

namespace OCA\PriNotes\Service;

use OCA\PriNotes\Db\Share;
use OCA\PriNotes\Db\ShareMapper;
use OCA\PriNotes\Db\NoteMapper;

class ShareService {
    public function __construct(
        private ShareMapper $shareMapper,
        private NoteMapper  $noteMapper,
    ) {}

    public function getSharesForNote(int $noteId, string $userId): array {
        $this->noteMapper->findById($noteId, $userId); // ownership check
        $shares = $this->shareMapper->findForNote($noteId, $userId);
        return array_map(fn(Share $s) => $s->jsonSerialize(), $shares);
    }

    public function createShare(int $noteId, string $userId, array $data): array {
        $this->noteMapper->findById($noteId, $userId); // ownership check

        $share = new Share();
        $share->setNoteId($noteId);
        $share->setOwnerId($userId);
        $share->setShareType($data['shareType'] ?? 'user');
        $share->setPermissions($data['permissions'] ?? 'read');
        $share->setCreatedAt(time());

        if ($share->getShareType() === 'user') {
            $share->setSharedWith($data['sharedWith'] ?? null);
        } else {
            // Generate public token
            $share->setToken(bin2hex(random_bytes(16)));
        }

        return $this->shareMapper->insert($share)->jsonSerialize();
    }

    public function deleteShare(int $noteId, int $shareId, string $userId): void {
        $this->noteMapper->findById($noteId, $userId); // ownership check
        $share = $this->shareMapper->findById($shareId, $userId);
        $this->shareMapper->delete($share);
    }

    public function getByToken(string $token): ?Share {
        try {
            return $this->shareMapper->findByToken($token);
        } catch (\Throwable) {
            return null;
        }
    }
}
