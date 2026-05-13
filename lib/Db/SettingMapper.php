<?php

declare(strict_types=1);

namespace OCA\PriNotes\Db;

use OCP\AppFramework\Db\Entity;
use OCP\AppFramework\Db\QBMapper;
use OCP\DB\QueryBuilder\IQueryBuilder;
use OCP\IDBConnection;

class Setting extends Entity {
    protected string $userId = '';
    protected string $key = '';
    protected ?string $value = null;
}

class SettingMapper extends QBMapper {
    public function __construct(IDBConnection $db) {
        parent::__construct($db, 'prinotes_settings', Setting::class);
    }

    public function get(string $userId, string $key): ?string {
        $qb = $this->db->getQueryBuilder();
        $qb->select('value')
            ->from($this->getTableName())
            ->where($qb->expr()->eq('user_id', $qb->createNamedParameter($userId)))
            ->andWhere($qb->expr()->eq('key', $qb->createNamedParameter($key)));
        $result = $qb->executeQuery();
        $row = $result->fetch();
        $result->closeCursor();
        return $row ? $row['value'] : null;
    }

    public function getAll(string $userId): array {
        $qb = $this->db->getQueryBuilder();
        $qb->select('key', 'value')
            ->from($this->getTableName())
            ->where($qb->expr()->eq('user_id', $qb->createNamedParameter($userId)));
        $result = $qb->executeQuery();
        $rows = $result->fetchAll();
        $result->closeCursor();
        $settings = [];
        foreach ($rows as $row) {
            $settings[$row['key']] = $row['value'];
        }
        return $settings;
    }

    public function set(string $userId, string $key, ?string $value): void {
        $existing = $this->get($userId, $key);
        if ($existing === null) {
            $qb = $this->db->getQueryBuilder();
            $qb->insert($this->getTableName())
                ->values([
                    'user_id' => $qb->createNamedParameter($userId),
                    'key'     => $qb->createNamedParameter($key),
                    'value'   => $qb->createNamedParameter($value),
                ]);
            $qb->executeStatement();
        } else {
            $qb = $this->db->getQueryBuilder();
            $qb->update($this->getTableName())
                ->set('value', $qb->createNamedParameter($value))
                ->where($qb->expr()->eq('user_id', $qb->createNamedParameter($userId)))
                ->andWhere($qb->expr()->eq('key', $qb->createNamedParameter($key)));
            $qb->executeStatement();
        }
    }
}
