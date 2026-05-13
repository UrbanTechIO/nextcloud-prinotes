<?php

declare(strict_types=1);

namespace OCA\PriNotes\Db;

use OCP\AppFramework\Db\Entity;

/**
 * @method string getUserId()
 * @method void setUserId(string $userId)
 * @method string getTitle()
 * @method void setTitle(string $title)
 * @method string|null getDescription()
 * @method void setDescription(?string $description)
 * @method string|null getColor()
 * @method void setColor(?string $color)
 * @method string|null getIcon()
 * @method void setIcon(?string $icon)
 * @method int getSortOrder()
 * @method void setSortOrder(int $sortOrder)
 * @method int getCreatedAt()
 * @method void setCreatedAt(int $createdAt)
 * @method int getUpdatedAt()
 * @method void setUpdatedAt(int $updatedAt)
 */
class Notebook extends Entity {
    protected string $userId = '';
    protected string $title = '';
    protected ?string $description = null;
    protected ?string $color = null;
    protected ?string $icon = null;
    protected int $sortOrder = 0;
    protected int $createdAt = 0;
    protected int $updatedAt = 0;

    public function jsonSerialize(): array {
        return [
            'id'          => $this->id,
            'title'       => $this->title,
            'description' => $this->description,
            'color'       => $this->color,
            'icon'        => $this->icon,
            'sortOrder'   => $this->sortOrder,
            'createdAt'   => $this->createdAt,
            'updatedAt'   => $this->updatedAt,
        ];
    }
}
