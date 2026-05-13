<?php

declare(strict_types=1);

namespace OCA\PriNotes\Db;

use OCP\AppFramework\Db\Entity;

/**
 * @method string getUserId()
 * @method void setUserId(string $userId)
 * @method int|null getNotebookId()
 * @method void setNotebookId(?int $notebookId)
 * @method string getTitle()
 * @method void setTitle(string $title)
 * @method string getContent()
 * @method void setContent(string $content)
 * @method string|null getPreview()
 * @method void setPreview(?string $preview)
 * @method string|null getColor()
 * @method void setColor(?string $color)
 * @method int getIsPinned()
 * @method void setIsPinned(int $isPinned)
 * @method int getIsArchived()
 * @method void setIsArchived(int $isArchived)
 * @method int getIsLocked()
 * @method void setIsLocked(int $isLocked)
 * @method string|null getLockPinHash()
 * @method void setLockPinHash(?string $lockPinHash)
 * @method int getIsTrashed()
 * @method void setIsTrashed(int $isTrashed)
 * @method int|null getTrashedAt()
 * @method void setTrashedAt(?int $trashedAt)
 * @method int getCreatedAt()
 * @method void setCreatedAt(int $createdAt)
 * @method int getUpdatedAt()
 * @method void setUpdatedAt(int $updatedAt)
 * @method int getVersion()
 * @method void setVersion(int $version)
 */
class Note extends Entity {
    protected string $userId = '';
    protected ?int $notebookId = null;
    protected string $title = '';
    protected string $content = '{}';
    protected ?string $preview = null;
    protected ?string $color = null;
    protected int $isPinned = 0;
    protected int $isArchived = 0;
    protected int $isLocked = 0;
    protected ?string $lockPinHash = null;
    protected int $isTrashed = 0;
    protected ?int $trashedAt = null;
    protected int $createdAt = 0;
    protected int $updatedAt = 0;
    protected int $version = 1;

    // Not stored in DB — populated by service layer
    public array $tags = [];

    public function jsonSerialize(bool $includeContent = true): array {
        $data = [
            'id'         => $this->id,
            'notebookId' => $this->notebookId,
            'title'      => $this->title,
            'preview'    => $this->preview,
            'color'      => $this->color,
            'isPinned'   => (bool)$this->isPinned,
            'isArchived' => (bool)$this->isArchived,
            'isLocked'   => (bool)$this->isLocked,
            'lockPinHash' => $this->lockPinHash,
            'isTrashed'  => (bool)$this->isTrashed,
            'trashedAt'  => $this->trashedAt,
            'createdAt'  => $this->createdAt,
            'updatedAt'  => $this->updatedAt,
            'version'    => $this->version,
            'tags'       => $this->tags,
            'hasMedia'   => $this->computeHasMedia(),
        ];
        if ($includeContent) {
            $data['content'] = $this->content;
        }
        return $data;
    }

    private function computeHasMedia(): bool {
        $c = $this->content ?? '';
        if (strlen($c) < 5) return false;
        if ($c[0] === '{') {
            // Check JSON content for any image or drawing data without full parse
            return strpos($c, '"image"') !== false
                || strpos($c, '"drawing"') !== false
                || strpos($c, '"strokes"') !== false
                || strpos($c, '"images"') !== false;
        }
        // Markdown: check for image syntax
        return strpos($c, '![') !== false;
    }
}
