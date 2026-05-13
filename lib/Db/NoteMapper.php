<?php

declare(strict_types=1);

namespace OCA\PriNotes\Db;

use OCP\AppFramework\Db\QBMapper;
use OCP\DB\QueryBuilder\IQueryBuilder;
use OCP\IDBConnection;

class NoteMapper extends QBMapper {
    public function __construct(IDBConnection $db) {
        parent::__construct($db, 'prinotes_notes', Note::class);
    }

    public function findAll(string $userId, ?int $notebookId = null, bool $trashed = false, bool $archived = false): array {
        $qb = $this->db->getQueryBuilder();
        $qb->select('n.*')
            ->from($this->getTableName(), 'n')
            ->where($qb->expr()->eq('n.user_id', $qb->createNamedParameter($userId)))
            ->andWhere($qb->expr()->eq('n.is_trashed', $qb->createNamedParameter($trashed ? 1 : 0, IQueryBuilder::PARAM_INT)));

        if (!$trashed) {
            $qb->andWhere($qb->expr()->eq('n.is_archived', $qb->createNamedParameter($archived ? 1 : 0, IQueryBuilder::PARAM_INT)));
        }

        if ($notebookId !== null) {
            $qb->andWhere($qb->expr()->eq('n.notebook_id', $qb->createNamedParameter($notebookId, IQueryBuilder::PARAM_INT)));
        }

        $qb->orderBy('n.is_pinned', 'DESC')
           ->addOrderBy('n.updated_at', 'DESC');

        return $this->findEntities($qb);
    }

    public function findById(int $id, string $userId): Note {
        $qb = $this->db->getQueryBuilder();
        $qb->select('*')
            ->from($this->getTableName())
            ->where($qb->expr()->eq('id', $qb->createNamedParameter($id, IQueryBuilder::PARAM_INT)))
            ->andWhere($qb->expr()->eq('user_id', $qb->createNamedParameter($userId)));
        return $this->findEntity($qb);
    }

    public function findByTag(string $userId, int $tagId): array {
        $qb = $this->db->getQueryBuilder();
        $qb->select('n.*')
            ->from($this->getTableName(), 'n')
            ->innerJoin('n', 'prinotes_note_tags', 'nt', 'n.id = nt.note_id')
            ->where($qb->expr()->eq('n.user_id', $qb->createNamedParameter($userId)))
            ->andWhere($qb->expr()->eq('nt.tag_id', $qb->createNamedParameter($tagId, IQueryBuilder::PARAM_INT)))
            ->andWhere($qb->expr()->eq('n.is_trashed', $qb->createNamedParameter(0, IQueryBuilder::PARAM_INT)))
            ->orderBy('n.is_pinned', 'DESC')
            ->addOrderBy('n.updated_at', 'DESC');
        return $this->findEntities($qb);
    }

    public function search(string $userId, string $query): array {
        $qb = $this->db->getQueryBuilder();
        $likeParam = $qb->createNamedParameter('%' . $this->db->escapeLikeParameter($query) . '%');
        $qb->select('*')
            ->from($this->getTableName())
            ->where($qb->expr()->eq('user_id', $qb->createNamedParameter($userId)))
            ->andWhere($qb->expr()->eq('is_trashed', $qb->createNamedParameter(0, IQueryBuilder::PARAM_INT)))
            ->andWhere(
                $qb->expr()->orX(
                    $qb->expr()->iLike('title', $likeParam),
                    $qb->expr()->iLike('content', $likeParam),
                    $qb->expr()->iLike('preview', $likeParam)
                )
            )
            ->orderBy('updated_at', 'DESC')
            ->setMaxResults(100);
        return $this->findEntities($qb);
    }

    public function findAllIds(string $userId): array {
        $qb = $this->db->getQueryBuilder();
        $qb->select('id')
            ->from($this->getTableName())
            ->where($qb->expr()->eq('user_id', $qb->createNamedParameter($userId)));
        $result = $qb->executeQuery();
        $ids = [];
        while ($row = $result->fetch()) {
            $ids[] = (int)$row['id'];
        }
        $result->closeCursor();
        return $ids;
    }

    public function findUpdatedSince(string $userId, int $since): array {
        // Subtract 60 seconds to handle clock-skew and boundary cases where
        // a note's updated_at equals the mobile's lastSync timestamp exactly.
        $threshold = max(0, $since - 60);
        $qb = $this->db->getQueryBuilder();
        $qb->select('*')
            ->from($this->getTableName())
            ->where($qb->expr()->eq('user_id', $qb->createNamedParameter($userId)))
            ->andWhere($qb->expr()->gt('updated_at', $qb->createNamedParameter($threshold, IQueryBuilder::PARAM_INT)));
        return $this->findEntities($qb);
    }

    public function findByIdPublic(int $id): Note {
        $qb = $this->db->getQueryBuilder();
        $qb->select('*')
            ->from($this->getTableName())
            ->where($qb->expr()->eq('id', $qb->createNamedParameter($id, IQueryBuilder::PARAM_INT)));
        return $this->findEntity($qb);
    }
}
