<?php

declare(strict_types=1);

namespace OCA\PriNotes\BackgroundJob;

use OCA\PriNotes\Service\VoiceFiles;
use OCP\AppFramework\Utility\ITimeFactory;
use OCP\BackgroundJob\TimedJob;
use OCP\Files\Folder;
use OCP\Files\IRootFolder;
use OCP\IDBConnection;
use OCP\IUser;
use OCP\IUserManager;

/**
 * Once a day, removes voice recordings (PriNotes/voice in the user's Files) that no note uses any more, for
 * example one deleted from a note on the web. Files younger than two days are never touched.
 */
class CleanupVoiceFilesJob extends TimedJob {
    public function __construct(
        ITimeFactory $time,
        private IUserManager $users,
        private IRootFolder $rootFolder,
        private IDBConnection $db,
    ) {
        parent::__construct($time);
        $this->setInterval(24 * 3600);
    }

    protected function run(mixed $argument): void {
        $this->users->callForSeenUsers(function (IUser $user): void {
            try {
                $this->cleanUser($user->getUID());
            } catch (\Throwable) {
                // One user's problem must not stop the others.
            }
        });
    }

    private function cleanUser(string $userId): void {
        $userFolder = $this->rootFolder->getUserFolder($userId);
        if (!$userFolder->nodeExists('PriNotes/voice')) {
            return;
        }
        $folder = $userFolder->get('PriNotes/voice');
        if (!$folder instanceof Folder) {
            return;
        }
        $now = time();
        foreach ($folder->getDirectoryListing() as $file) {
            $id = VoiceFiles::idFromName($file->getName());
            if ($id === null || !VoiceFiles::isOldEnough($file->getMTime(), $now)) {
                continue;
            }
            if (!$this->isUsed($userId, $id)) {
                $file->delete();
            }
        }
    }

    /** True when any of the user's notes (trashed ones too) mentions the recording. */
    private function isUsed(string $userId, string $id): bool {
        $qb = $this->db->getQueryBuilder();
        $qb->select('id')
            ->from('prinotes_notes')
            ->where($qb->expr()->eq('user_id', $qb->createNamedParameter($userId)))
            ->andWhere($qb->expr()->like('content', $qb->createNamedParameter('%' . $this->db->escapeLikeParameter($id) . '%')))
            ->setMaxResults(1);
        $result = $qb->executeQuery();
        $found = $result->fetchOne();
        $result->closeCursor();
        return $found !== false;
    }
}
