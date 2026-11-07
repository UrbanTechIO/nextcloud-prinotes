<?php

declare(strict_types=1);

namespace OCA\PriNotes\Db;

use OCP\AppFramework\Db\Entity;

/**
 * @method string getUserId()
 * @method void setUserId(string $userId)
 * @method int|null getParentId()
 * @method void setParentId(?int $parentId)
 * @method string getTitle()
 * @method void setTitle(string $title)
 * @method string|null getColor()
 * @method void setColor(?string $color)
 * @method int getSortOrder()
 * @method void setSortOrder(int $sortOrder)
 * @method int getIsSystem()
 * @method void setIsSystem(int $isSystem)
 * @method string|null getSystemKey()
 * @method void setSystemKey(?string $systemKey)
 * @method int getCreatedAt()
 * @method void setCreatedAt(int $createdAt)
 * @method int getUpdatedAt()
 * @method void setUpdatedAt(int $updatedAt)
 */
class TodoList extends Entity {
    protected string $userId = '';
    protected ?int $parentId = null;
    protected string $title = '';
    protected ?string $color = null;
    protected int $sortOrder = 0;
    protected int $isSystem = 0;
    protected ?string $systemKey = null;
    protected int $createdAt = 0;
    protected int $updatedAt = 0;

    public function jsonSerialize(): array {
        return [
            'id'        => $this->id,
            'parentId'  => $this->parentId,
            'title'     => $this->title,
            'color'     => $this->color,
            'sortOrder' => $this->sortOrder,
            'isSystem'  => $this->isSystem === 1,
            'createdAt' => $this->createdAt,
            'updatedAt' => $this->updatedAt,
        ];
    }
}
