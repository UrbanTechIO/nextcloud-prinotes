<?php

declare(strict_types=1);

namespace OCA\PriNotes\Db;

use OCP\AppFramework\Db\QBMapper;
use OCP\DB\QueryBuilder\IQueryBuilder;
use OCP\IDBConnection;

class ShareMapper extends QBMapper {
    public function __construct(IDBConnection $db) {
        parent::__construct($db, 'prinotes_shares', Share::class);
    }

    public function findForNote(int $noteId, string $ownerId): array {
        $qb = $this->db->getQueryBuilder();
        $qb->select('*')
            ->from($this->getTableName())
            ->where($qb->expr()->eq('note_id', $qb->createNamedParameter($noteId, IQueryBuilder::PARAM_INT)))
            ->andWhere($qb->expr()->eq('owner_id', $qb->createNamedParameter($ownerId)));
        return $this->findEntities($qb);
    }

    public function findByToken(string $token): Share {
        $qb = $this->db->getQueryBuilder();
        $qb->select('*')
            ->from($this->getTableName())
            ->where($qb->expr()->eq('token', $qb->createNamedParameter($token)));
        return $this->findEntity($qb);
    }

    public function findById(int $id, string $ownerId): Share {
        $qb = $this->db->getQueryBuilder();
        $qb->select('*')
            ->from($this->getTableName())
            ->where($qb->expr()->eq('id', $qb->createNamedParameter($id, IQueryBuilder::PARAM_INT)))
            ->andWhere($qb->expr()->eq('owner_id', $qb->createNamedParameter($ownerId)));
        return $this->findEntity($qb);
    }

    public function deleteAllForNote(int $noteId): void {
        $qb = $this->db->getQueryBuilder();
        $qb->delete($this->getTableName())
            ->where($qb->expr()->eq('note_id', $qb->createNamedParameter($noteId, IQueryBuilder::PARAM_INT)));
        $qb->executeStatement();
    }
}
