<?php

declare(strict_types=1);

namespace OCA\PriNotes\Db;

use OCP\AppFramework\Db\Entity;
use OCP\AppFramework\Db\QBMapper;
use OCP\DB\QueryBuilder\IQueryBuilder;
use OCP\IDBConnection;

class Attachment extends Entity {
    protected int $noteId = 0;
    protected string $userId = '';
    protected string $filename = '';
    protected string $mimeType = '';
    protected int $size = 0;
    protected ?int $ncFileId = null;
    protected int $createdAt = 0;
}

class AttachmentMapper extends QBMapper {
    public function __construct(IDBConnection $db) {
        parent::__construct($db, 'prinotes_attachments', Attachment::class);
    }

    public function findById(int $id, string $userId): Attachment {
        $qb = $this->db->getQueryBuilder();
        $qb->select('*')
            ->from($this->getTableName())
            ->where($qb->expr()->eq('id', $qb->createNamedParameter($id, IQueryBuilder::PARAM_INT)))
            ->andWhere($qb->expr()->eq('user_id', $qb->createNamedParameter($userId)));
        return $this->findEntity($qb);
    }
}
