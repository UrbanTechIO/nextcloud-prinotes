<?php

declare(strict_types=1);

namespace OCA\PriNotes\Db;

use OCP\AppFramework\Db\QBMapper;
use OCP\DB\QueryBuilder\IQueryBuilder;
use OCP\IDBConnection;

class TodoMapper extends QBMapper {
    public function __construct(IDBConnection $db) {
        parent::__construct($db, 'prinotes_todos', Todo::class);
    }

    /** @return Todo[] */
    public function findAll(string $userId): array {
        $qb = $this->db->getQueryBuilder();
        $qb->select('*')
            ->from($this->getTableName())
            ->where($qb->expr()->eq('user_id', $qb->createNamedParameter($userId)))
            ->orderBy('sort_order', 'ASC')
            ->addOrderBy('id', 'ASC');
        return $this->findEntities($qb);
    }

    public function findById(int $id, string $userId): Todo {
        $qb = $this->db->getQueryBuilder();
        $qb->select('*')
            ->from($this->getTableName())
            ->where($qb->expr()->eq('id', $qb->createNamedParameter($id, IQueryBuilder::PARAM_INT)))
            ->andWhere($qb->expr()->eq('user_id', $qb->createNamedParameter($userId)));
        return $this->findEntity($qb);
    }

    /** @return Todo[] */
    public function findUpdatedSince(string $userId, int $since): array {
        $qb = $this->db->getQueryBuilder();
        $qb->select('*')
            ->from($this->getTableName())
            ->where($qb->expr()->eq('user_id', $qb->createNamedParameter($userId)))
            ->andWhere($qb->expr()->gte('updated_at', $qb->createNamedParameter($since, IQueryBuilder::PARAM_INT)));
        return $this->findEntities($qb);
    }

    /** @return int[] */
    public function findAllIds(string $userId): array {
        $qb = $this->db->getQueryBuilder();
        $qb->select('id')
            ->from($this->getTableName())
            ->where($qb->expr()->eq('user_id', $qb->createNamedParameter($userId)));
        $result = $qb->executeQuery();
        $ids = array_map('intval', $result->fetchAll(\PDO::FETCH_COLUMN));
        $result->closeCursor();
        return $ids;
    }

    /** @return Todo[] */
    public function findDueReminders(int $now): array {
        $qb = $this->db->getQueryBuilder();
        $qb->select('*')
            ->from($this->getTableName())
            ->where($qb->expr()->eq('is_done', $qb->createNamedParameter(0, IQueryBuilder::PARAM_INT)))
            ->andWhere($qb->expr()->eq('reminder_sent', $qb->createNamedParameter(0, IQueryBuilder::PARAM_INT)))
            ->andWhere($qb->expr()->isNotNull('remind_at'))
            ->andWhere($qb->expr()->lte('remind_at', $qb->createNamedParameter($now, IQueryBuilder::PARAM_INT)));
        return $this->findEntities($qb);
    }

    /** @return Todo[] */
    public function findByList(int $listId, string $userId): array {
        $qb = $this->db->getQueryBuilder();
        $qb->select('*')
            ->from($this->getTableName())
            ->where($qb->expr()->eq('user_id', $qb->createNamedParameter($userId)))
            ->andWhere($qb->expr()->eq('list_id', $qb->createNamedParameter($listId, IQueryBuilder::PARAM_INT)));
        return $this->findEntities($qb);
    }

    public function deleteByList(int $listId, string $userId): void {
        $qb = $this->db->getQueryBuilder();
        $qb->delete($this->getTableName())
            ->where($qb->expr()->eq('user_id', $qb->createNamedParameter($userId)))
            ->andWhere($qb->expr()->eq('list_id', $qb->createNamedParameter($listId, IQueryBuilder::PARAM_INT)));
        $qb->executeStatement();
    }
}
