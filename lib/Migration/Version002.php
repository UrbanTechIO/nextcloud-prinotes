<?php

declare(strict_types=1);

namespace OCA\PriNotes\Migration;

use Closure;
use OCP\DB\ISchemaWrapper;
use OCP\DB\Types;
use OCP\Migration\IOutput;
use OCP\Migration\SimpleMigrationStep;

/** Adds the To-Do tables. Additive only: existing tables are never touched. */
class Version002 extends SimpleMigrationStep {

    public function changeSchema(IOutput $output, Closure $schemaClosure, array $options): ?ISchemaWrapper {
        /** @var ISchemaWrapper $schema */
        $schema = $schemaClosure();

        if (!$schema->hasTable('prinotes_todo_lists')) {
            $table = $schema->createTable('prinotes_todo_lists');
            $table->addColumn('id', Types::BIGINT, ['autoincrement' => true, 'notnull' => true]);
            $table->addColumn('user_id', Types::STRING, ['notnull' => true, 'length' => 64]);
            $table->addColumn('parent_id', Types::BIGINT, ['notnull' => false, 'default' => null]);
            $table->addColumn('title', Types::STRING, ['notnull' => true, 'length' => 255]);
            $table->addColumn('color', Types::STRING, ['notnull' => false, 'length' => 16, 'default' => null]);
            $table->addColumn('sort_order', Types::INTEGER, ['notnull' => true, 'default' => 0]);
            $table->addColumn('is_system', Types::SMALLINT, ['notnull' => true, 'default' => 0]);
            $table->addColumn('system_key', Types::STRING, ['notnull' => false, 'length' => 16, 'default' => null]);
            $table->addColumn('created_at', Types::BIGINT, ['notnull' => true, 'default' => 0]);
            $table->addColumn('updated_at', Types::BIGINT, ['notnull' => true, 'default' => 0]);
            $table->setPrimaryKey(['id']);
            $table->addIndex(['user_id'], 'prinotes_tl_user');
            $table->addUniqueIndex(['user_id', 'system_key'], 'prinotes_tl_sys');
        }

        if (!$schema->hasTable('prinotes_todos')) {
            $table = $schema->createTable('prinotes_todos');
            $table->addColumn('id', Types::BIGINT, ['autoincrement' => true, 'notnull' => true]);
            $table->addColumn('user_id', Types::STRING, ['notnull' => true, 'length' => 64]);
            $table->addColumn('list_id', Types::BIGINT, ['notnull' => true, 'default' => 0]);
            $table->addColumn('title', Types::STRING, ['notnull' => true, 'length' => 500, 'default' => '']);
            $table->addColumn('note', Types::TEXT, ['notnull' => false, 'default' => null]);
            $table->addColumn('is_done', Types::SMALLINT, ['notnull' => true, 'default' => 0]);
            $table->addColumn('done_at', Types::BIGINT, ['notnull' => false, 'default' => null]);
            $table->addColumn('due_date', Types::STRING, ['notnull' => false, 'length' => 10, 'default' => null]);
            $table->addColumn('remind_at', Types::BIGINT, ['notnull' => false, 'default' => null]);
            $table->addColumn('reminder_sent', Types::SMALLINT, ['notnull' => true, 'default' => 0]);
            $table->addColumn('next_spawned', Types::SMALLINT, ['notnull' => true, 'default' => 0]);
            $table->addColumn('repeat_rule', Types::STRING, ['notnull' => false, 'length' => 16, 'default' => null]);
            $table->addColumn('is_important', Types::SMALLINT, ['notnull' => true, 'default' => 0]);
            $table->addColumn('steps', Types::TEXT, ['notnull' => false, 'default' => null]);
            $table->addColumn('sort_order', Types::INTEGER, ['notnull' => true, 'default' => 0]);
            $table->addColumn('created_at', Types::BIGINT, ['notnull' => true, 'default' => 0]);
            $table->addColumn('updated_at', Types::BIGINT, ['notnull' => true, 'default' => 0]);
            $table->addColumn('version', Types::INTEGER, ['notnull' => true, 'default' => 1]);
            $table->setPrimaryKey(['id']);
            $table->addIndex(['user_id'], 'prinotes_td_user');
            $table->addIndex(['user_id', 'list_id'], 'prinotes_td_list');
            $table->addIndex(['user_id', 'updated_at'], 'prinotes_td_upd');
            $table->addIndex(['remind_at'], 'prinotes_td_rem');
        }

        return $schema;
    }
}
