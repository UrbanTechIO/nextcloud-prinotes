<?php

declare(strict_types=1);

namespace OCA\PriNotes\Service;

use OCA\PriNotes\Db\Note;
use OCA\PriNotes\Db\NoteMapper;
use OCA\PriNotes\Db\NoteVersion;
use OCA\PriNotes\Db\NoteVersionMapper;
use OCA\PriNotes\Db\TagMapper;
use OCA\PriNotes\Db\ShareMapper;
use OCA\PriNotes\Db\ReminderMapper;
use OCP\AppFramework\Db\DoesNotExistException;
use OCP\ILogger;

class NoteService {
    public function __construct(
        private NoteMapper        $noteMapper,
        private NoteVersionMapper $versionMapper,
        private TagMapper         $tagMapper,
        private ShareMapper       $shareMapper,
        private ReminderMapper    $reminderMapper,
        private SettingsService   $settings,
    ) {}

    public function getAll(string $userId, ?int $notebookId = null, bool $trashed = false, bool $archived = false): array {
        $notes = $this->noteMapper->findAll($userId, $notebookId, $trashed, $archived);
        return array_map(fn(Note $n) => $this->hydrate($n), $notes);
    }

    public function getByTag(string $userId, int $tagId): array {
        $notes = $this->noteMapper->findByTag($userId, $tagId);
        return array_map(fn(Note $n) => $this->hydrate($n), $notes);
    }

    public function search(string $userId, string $query): array {
        $notes = $this->noteMapper->search($userId, $query);
        return array_map(fn(Note $n) => $this->hydrate($n), $notes);
    }

    public function get(int $id, string $userId): array {
        $note = $this->noteMapper->findById($id, $userId);
        return $this->hydrate($note, includeContent: true);
    }

    public function create(string $userId, array $data): array {
        $now = time();
        $note = new Note();
        $note->setUserId($userId);
        $note->setTitle($data['title'] ?? '');
        $note->setContent($data['content'] ?? '{"version":"1.0","blocks":[]}');
        $note->setPreview($this->extractPreview($data['content'] ?? ''));
        $note->setColor($data['color'] ?? null);
        $note->setNotebookId(isset($data['notebookId']) ? (int)$data['notebookId'] : null);
        $note->setIsPinned(isset($data['isPinned']) ? (int)(bool)$data['isPinned'] : 0);
        $note->setIsArchived(0);
        $note->setIsLocked(isset($data['isLocked']) ? (int)(bool)$data['isLocked'] : 0);
        $note->setLockPinHash($data['lockPinHash'] ?? null);
        $isTrashed = isset($data['isTrashed']) && (bool)$data['isTrashed'];
        $note->setIsTrashed($isTrashed ? 1 : 0);
        $note->setTrashedAt($isTrashed ? $now : null);
        $note->setVersion(1);
        $note->setCreatedAt($now);
        $note->setUpdatedAt($now);

        $note = $this->noteMapper->insert($note);

        // Accept both array of IDs and empty array so tags sync correctly from mobile
        if (array_key_exists('tags', $data)) {
            $this->tagMapper->setTagsForNote($note->getId(), (array)$data['tags']);
        }

        return $this->hydrate($note, includeContent: true);
    }

    public function update(int $id, string $userId, array $data): array {
        $note = $this->noteMapper->findById($id, $userId);

        // Save version before updating (if history enabled)
        $historyEnabled = $this->settings->get($userId, 'version_history_enabled', 'true') === 'true';
        if ($historyEnabled && isset($data['content'])) {
            $this->saveVersion($note, $userId);
            $this->pruneVersions($note->getId(), $userId);
        }

        if (array_key_exists('title', $data)) {
            $note->setTitle($data['title']);
        }
        if (array_key_exists('content', $data)) {
            $note->setContent($data['content']);
            $note->setPreview($this->extractPreview($data['content']));
        }
        if (array_key_exists('color', $data)) {
            $note->setColor($data['color']);
        }
        if (array_key_exists('notebookId', $data)) {
            $note->setNotebookId($data['notebookId'] !== null ? (int)$data['notebookId'] : null);
        }
        if (array_key_exists('isPinned', $data)) {
            $note->setIsPinned((int)(bool)$data['isPinned']);
        }
        if (array_key_exists('isArchived', $data)) {
            $note->setIsArchived((int)(bool)$data['isArchived']);
        }
        if (array_key_exists('isLocked', $data)) {
            $note->setIsLocked((int)(bool)$data['isLocked']);
        }
        if (array_key_exists('lockPinHash', $data)) {
            // Safety guard: never wipe the hash while the note stays locked.
            // A null hash is only valid when the note is also being unlocked in
            // the same request (e.g. web LockDialog sends isLocked:false +
            // lockPinHash:null together).  Any other null — e.g. a client that
            // sends lockPinHash:null without changing isLocked — is ignored so
            // the existing hash is preserved.
            $noteIsLocked = (bool)$note->getIsLocked(); // already updated above
            $clearingHash = $data['lockPinHash'] === null;
            if (!$clearingHash || !$noteIsLocked) {
                $note->setLockPinHash($data['lockPinHash']);
            }
        }
        if (array_key_exists('isTrashed', $data)) {
            $note->setIsTrashed((int)(bool)$data['isTrashed']);
            if ($data['isTrashed']) {
                $note->setTrashedAt(time());
            } else {
                $note->setTrashedAt(null);
            }
        }

        $note->setVersion($note->getVersion() + 1);
        $note->setUpdatedAt(time());
        $note = $this->noteMapper->update($note);

        if (array_key_exists('tags', $data)) {
            $this->tagMapper->setTagsForNote($note->getId(), $data['tags']);
        }

        return $this->hydrate($note, includeContent: true);
    }

    public function trash(int $id, string $userId): void {
        $note = $this->noteMapper->findById($id, $userId);
        $note->setIsTrashed(1);
        $note->setTrashedAt(time());
        // Increment version so the mobile's version-based conflict resolution
        // can detect this change even when the local note has pending changes.
        $note->setVersion($note->getVersion() + 1);
        $note->setUpdatedAt(time());
        $this->noteMapper->update($note);
    }

    public function restore(int $id, string $userId): array {
        $note = $this->noteMapper->findById($id, $userId);
        $note->setIsTrashed(0);
        $note->setTrashedAt(null);
        // Increment version so mobile detects the restore.
        $note->setVersion($note->getVersion() + 1);
        $note->setUpdatedAt(time());
        $note = $this->noteMapper->update($note);
        return $this->hydrate($note, includeContent: true);
    }

    public function delete(int $id, string $userId): void {
        $note = $this->noteMapper->findById($id, $userId);
        // Only allow permanent delete if already trashed
        $this->tagMapper->removeAllTagsFromNote($id);
        $this->versionMapper->deleteAllForNote($id);
        $this->shareMapper->deleteAllForNote($id);
        $this->noteMapper->delete($note);
    }

    // ── Versions ──────────────────────────────────────────────────────────────

    public function getVersions(int $noteId, string $userId): array {
        $this->noteMapper->findById($noteId, $userId); // ownership check
        $versions = $this->versionMapper->findAllForNote($noteId, $userId);
        return array_map(fn(NoteVersion $v) => $v->jsonSerialize(), $versions);
    }

    public function restoreVersion(int $noteId, int $versionId, string $userId): array {
        $note    = $this->noteMapper->findById($noteId, $userId);
        $version = $this->versionMapper->findById($versionId, $userId);

        $this->saveVersion($note, $userId); // save current as new version before restoring
        $note->setTitle($version->getTitle());
        $note->setContent($version->getContent());
        $note->setPreview($this->extractPreview($version->getContent()));
        $note->setVersion($note->getVersion() + 1);
        $note->setUpdatedAt(time());
        $note = $this->noteMapper->update($note);

        return $this->hydrate($note, includeContent: true);
    }

    public function deleteVersion(int $noteId, int $versionId, string $userId): void {
        $this->noteMapper->findById($noteId, $userId); // ownership check
        $version = $this->versionMapper->findById($versionId, $userId);
        $this->versionMapper->delete($version);
    }

    public function getAllIds(string $userId): array {
        return $this->noteMapper->findAllIds($userId);
    }

    public function getUpdatedSince(string $userId, int $since): array {
        $notes = $this->noteMapper->findUpdatedSince($userId, $since);
        return array_map(fn(Note $n) => $this->hydrate($n, includeContent: true), $notes);
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    private function hydrate(Note $note, bool $includeContent = false): array {
        $tags = $this->tagMapper->findTagsForNote($note->getId());
        $note->tags = array_map(fn($t) => $t->jsonSerialize(), $tags);
        return $note->jsonSerialize($includeContent);
    }

    private function saveVersion(Note $note, string $userId): void {
        $version = new NoteVersion();
        $version->setNoteId($note->getId());
        $version->setUserId($userId);
        $version->setTitle($note->getTitle());
        $version->setContent($note->getContent());
        $version->setVersionNumber($note->getVersion());
        $version->setCreatedAt(time());
        $this->versionMapper->insert($version);
    }

    private function pruneVersions(int $noteId, string $userId): void {
        $maxAgeDays = (int)$this->settings->get($userId, 'version_history_days', '30');
        if ($maxAgeDays > 0) {
            $cutoff = time() - ($maxAgeDays * 86400);
            $this->versionMapper->deleteOlderThan($noteId, $cutoff);
        }
    }

    private function extractPreview(string $contentJson): string {
        try {
            $data = json_decode($contentJson, true, 512, JSON_THROW_ON_ERROR);
            $text = '';

            // quill-1.0 format: { version: 'quill-1.0', delta: [{insert: '...'}...] }
            if (($data['version'] ?? '') === 'quill-1.0') {
                foreach ($data['delta'] ?? [] as $op) {
                    if (is_string($op['insert'] ?? null)) {
                        $text .= $op['insert']; // keep \n so the card can show line structure
                    }
                    if (mb_strlen($text) > 300) break;
                }
                $text = preg_replace('/\n{3,}/', "\n\n", $text); // collapse excess blank lines
                return mb_substr(trim($text), 0, 300);
            }

            // v2.0 uses 'paragraphs', v1.0 uses 'blocks'
            $blocks = $data['paragraphs'] ?? $data['blocks'] ?? [];
            foreach ($blocks as $block) {
                $type = $block['type'] ?? '';
                if (in_array($type, ['paragraph', 'heading', 'quote'])) {
                    $inline = $block['content'] ?? [];
                    foreach ($inline as $span) {
                        $text .= $span['text'] ?? '';
                    }
                } elseif ($type === 'checklist') {
                    foreach ($block['items'] ?? [] as $item) {
                        $text .= ($item['text'] ?? '') . ' ';
                    }
                } elseif ($type === 'list') {
                    foreach ($block['items'] ?? [] as $item) {
                        $text .= ($item['text'] ?? '') . ' ';
                    }
                }
                $text .= ' ';
                if (mb_strlen($text) > 300) break;
            }
            return mb_substr(trim($text), 0, 300);
        } catch (\Throwable) {
            // Not JSON — treat as Markdown / plain text, strip markup
            $text = preg_replace('/!?\[([^\]]*)\]\([^)]*\)/', '$1', $contentJson); // links/images
            $text = preg_replace('/^#{1,6}\s+/m', '', $text);                      // headings
            $text = preg_replace('/[*_~`]+/', '', $text);                           // inline formatting
            $text = preg_replace('/^\s*[-*+>]\s+/m', '', $text);                   // list/quote markers
            $text = preg_replace('/\r?\n+/', ' ', $text);                           // newlines → space
            return mb_substr(trim(preg_replace('/\s+/', ' ', $text)), 0, 300);
        }
    }
}
