<?php

declare(strict_types=1);

namespace OCA\PriNotes\Db;

use OCP\AppFramework\Db\DoesNotExistException;
use OCP\AppFramework\Db\QBMapper;
use OCP\DB\QueryBuilder\IQueryBuilder;
use OCP\IDBConnection;

class TodoListMapper extends QBMapper {
    public function __construct(IDBConnection $db) {
        parent::__construct($db, 'prinotes_todo_lists', TodoList::class);
    }

    /** @return TodoList[] */
    public function findAll(string $userId): array {
        $qb = $this->db->getQueryBuilder();
        $qb->select('*')
            ->from($this->getTableName())
            ->where($qb->expr()->eq('user_id', $qb->createNamedParameter($userId)))
            ->orderBy('sort_order', 'ASC')
            ->addOrderBy('title', 'ASC');
        return $this->findEntities($qb);
    }

    public function findById(int $id, string $userId): TodoList {
        $qb = $this->db->getQueryBuilder();
        $qb->select('*')
            ->from($this->getTableName())
            ->where($qb->expr()->eq('id', $qb->createNamedParameter($id, IQueryBuilder::PARAM_INT)))
            ->andWhere($qb->expr()->eq('user_id', $qb->createNamedParameter($userId)));
        return $this->findEntity($qb);
    }

    public function findInbox(string $userId): ?TodoList {
        $qb = $this->db->getQueryBuilder();
        $qb->select('*')
            ->from($this->getTableName())
            ->where($qb->expr()->eq('user_id', $qb->createNamedParameter($userId)))
            ->andWhere($qb->expr()->eq('system_key', $qb->createNamedParameter('inbox')));
        try {
            return $this->findEntity($qb);
        } catch (DoesNotExistException) {
            return null;
        }
    }

    /** @return TodoList[] */
    public function findChildren(int $parentId, string $userId): array {
        $qb = $this->db->getQueryBuilder();
        $qb->select('*')
            ->from($this->getTableName())
            ->where($qb->expr()->eq('user_id', $qb->createNamedParameter($userId)))
            ->andWhere($qb->expr()->eq('parent_id', $qb->createNamedParameter($parentId, IQueryBuilder::PARAM_INT)));
        return $this->findEntities($qb);
    }
}
