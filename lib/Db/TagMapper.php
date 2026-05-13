<?php

declare(strict_types=1);

namespace OCA\PriNotes\Db;

use OCP\AppFramework\Db\QBMapper;
use OCP\DB\QueryBuilder\IQueryBuilder;
use OCP\IDBConnection;

class TagMapper extends QBMapper {
    public function __construct(IDBConnection $db) {
        parent::__construct($db, 'prinotes_tags', Tag::class);
    }

    public function findAll(string $userId): array {
        $qb = $this->db->getQueryBuilder();
        $qb->select('*')
            ->from($this->getTableName())
            ->where($qb->expr()->eq('user_id', $qb->createNamedParameter($userId)))
            ->orderBy('name', 'ASC');
        return $this->findEntities($qb);
    }

    public function findById(int $id, string $userId): Tag {
        $qb = $this->db->getQueryBuilder();
        $qb->select('*')
            ->from($this->getTableName())
            ->where($qb->expr()->eq('id', $qb->createNamedParameter($id, IQueryBuilder::PARAM_INT)))
            ->andWhere($qb->expr()->eq('user_id', $qb->createNamedParameter($userId)));
        return $this->findEntity($qb);
    }

    public function findTagsForNote(int $noteId): array {
        $qb = $this->db->getQueryBuilder();
        $qb->select('t.*')
            ->from($this->getTableName(), 't')
            ->innerJoin('t', 'prinotes_note_tags', 'nt', 't.id = nt.tag_id')
            ->where($qb->expr()->eq('nt.note_id', $qb->createNamedParameter($noteId, IQueryBuilder::PARAM_INT)));
        return $this->findEntities($qb);
    }

    public function setTagsForNote(int $noteId, array $tagIds): void {
        // Delete existing
        $qb = $this->db->getQueryBuilder();
        $qb->delete('prinotes_note_tags')
            ->where($qb->expr()->eq('note_id', $qb->createNamedParameter($noteId, IQueryBuilder::PARAM_INT)));
        $qb->executeStatement();

        // Insert new
        foreach ($tagIds as $tagId) {
            $qb = $this->db->getQueryBuilder();
            $qb->insert('prinotes_note_tags')
                ->values([
                    'note_id' => $qb->createNamedParameter($noteId, IQueryBuilder::PARAM_INT),
                    'tag_id'  => $qb->createNamedParameter((int)$tagId, IQueryBuilder::PARAM_INT),
                ]);
            $qb->executeStatement();
        }
    }

    public function removeAllTagsFromNote(int $noteId): void {
        $qb = $this->db->getQueryBuilder();
        $qb->delete('prinotes_note_tags')
            ->where($qb->expr()->eq('note_id', $qb->createNamedParameter($noteId, IQueryBuilder::PARAM_INT)));
        $qb->executeStatement();
    }
}
