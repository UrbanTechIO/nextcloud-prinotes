<?php

declare(strict_types=1);

namespace OCA\PriNotes\Migration;

use Closure;
use OCP\DB\ISchemaWrapper;
use OCP\DB\Types;
use OCP\Migration\IOutput;
use OCP\Migration\SimpleMigrationStep;

class Version001 extends SimpleMigrationStep {

    public function changeSchema(IOutput $output, Closure $schemaClosure, array $options): ?ISchemaWrapper {
        /** @var ISchemaWrapper $schema */
        $schema = $schemaClosure();

        // ── Notebooks ─────────────────────────────────────────────────────────
        if (!$schema->hasTable('prinotes_notebooks')) {
            $table = $schema->createTable('prinotes_notebooks');
            $table->addColumn('id', Types::BIGINT, ['autoincrement' => true, 'notnull' => true]);
            $table->addColumn('user_id', Types::STRING, ['notnull' => true, 'length' => 64]);
            $table->addColumn('title', Types::STRING, ['notnull' => true, 'length' => 255]);
            $table->addColumn('description', Types::TEXT, ['notnull' => false, 'default' => null]);
            $table->addColumn('color', Types::STRING, ['notnull' => false, 'length' => 16, 'default' => null]);
            $table->addColumn('icon', Types::STRING, ['notnull' => false, 'length' => 64, 'default' => null]);
            $table->addColumn('sort_order', Types::INTEGER, ['notnull' => true, 'default' => 0]);
            $table->addColumn('created_at', Types::BIGINT, ['notnull' => true, 'default' => 0]);
            $table->addColumn('updated_at', Types::BIGINT, ['notnull' => true, 'default' => 0]);
            $table->setPrimaryKey(['id']);
            $table->addIndex(['user_id'], 'prinotes_nb_user');
        }

        // ── Notes ─────────────────────────────────────────────────────────────
        if (!$schema->hasTable('prinotes_notes')) {
            $table = $schema->createTable('prinotes_notes');
            $table->addColumn('id', Types::BIGINT, ['autoincrement' => true, 'notnull' => true]);
            $table->addColumn('user_id', Types::STRING, ['notnull' => true, 'length' => 64]);
            $table->addColumn('notebook_id', Types::BIGINT, ['notnull' => false, 'default' => null]);
            $table->addColumn('title', Types::STRING, ['notnull' => true, 'length' => 500, 'default' => '']);
            $table->addColumn('content', Types::TEXT, ['notnull' => true, 'default' => '{}']);
            $table->addColumn('preview', Types::TEXT, ['notnull' => false, 'default' => null]);
            $table->addColumn('color', Types::STRING, ['notnull' => false, 'length' => 16, 'default' => null]);
            $table->addColumn('is_pinned', Types::SMALLINT, ['notnull' => true, 'default' => 0]);
            $table->addColumn('is_archived', Types::SMALLINT, ['notnull' => true, 'default' => 0]);
            $table->addColumn('is_locked', Types::SMALLINT, ['notnull' => true, 'default' => 0]);
            $table->addColumn('lock_pin_hash', Types::STRING, ['notnull' => false, 'length' => 255, 'default' => null]);
            $table->addColumn('is_trashed', Types::SMALLINT, ['notnull' => true, 'default' => 0]);
            $table->addColumn('trashed_at', Types::BIGINT, ['notnull' => false, 'default' => null]);
            $table->addColumn('created_at', Types::BIGINT, ['notnull' => true, 'default' => 0]);
            $table->addColumn('updated_at', Types::BIGINT, ['notnull' => true, 'default' => 0]);
            $table->addColumn('version', Types::INTEGER, ['notnull' => true, 'default' => 1]);
            $table->setPrimaryKey(['id']);
            $table->addIndex(['user_id'], 'prinotes_note_user');
            $table->addIndex(['user_id', 'notebook_id'], 'prinotes_note_nb');
            $table->addIndex(['user_id', 'is_trashed'], 'prinotes_note_trash');
            $table->addIndex(['updated_at'], 'prinotes_note_updated');
        }

        // ── Tags ──────────────────────────────────────────────────────────────
        if (!$schema->hasTable('prinotes_tags')) {
            $table = $schema->createTable('prinotes_tags');
            $table->addColumn('id', Types::BIGINT, ['autoincrement' => true, 'notnull' => true]);
            $table->addColumn('user_id', Types::STRING, ['notnull' => true, 'length' => 64]);
            $table->addColumn('name', Types::STRING, ['notnull' => true, 'length' => 100]);
            $table->addColumn('color', Types::STRING, ['notnull' => false, 'length' => 16, 'default' => null]);
            $table->addColumn('created_at', Types::BIGINT, ['notnull' => true, 'default' => 0]);
            $table->setPrimaryKey(['id']);
            $table->addIndex(['user_id'], 'prinotes_tag_user');
            $table->addUniqueIndex(['user_id', 'name'], 'prinotes_tag_unique');
        }

        // ── Note ↔ Tag pivot ──────────────────────────────────────────────────
        if (!$schema->hasTable('prinotes_note_tags')) {
            $table = $schema->createTable('prinotes_note_tags');
            $table->addColumn('note_id', Types::BIGINT, ['notnull' => true]);
            $table->addColumn('tag_id', Types::BIGINT, ['notnull' => true]);
            $table->setPrimaryKey(['note_id', 'tag_id']);
            $table->addIndex(['tag_id'], 'prinotes_nt_tag');
        }

        // ── Note versions ─────────────────────────────────────────────────────
        if (!$schema->hasTable('prinotes_versions')) {
            $table = $schema->createTable('prinotes_versions');
            $table->addColumn('id', Types::BIGINT, ['autoincrement' => true, 'notnull' => true]);
            $table->addColumn('note_id', Types::BIGINT, ['notnull' => true]);
            $table->addColumn('user_id', Types::STRING, ['notnull' => true, 'length' => 64]);
            $table->addColumn('title', Types::STRING, ['notnull' => true, 'length' => 500, 'default' => '']);
            $table->addColumn('content', Types::TEXT, ['notnull' => true, 'default' => '{}']);
            $table->addColumn('version_number', Types::INTEGER, ['notnull' => true, 'default' => 1]);
            $table->addColumn('created_at', Types::BIGINT, ['notnull' => true, 'default' => 0]);
            $table->setPrimaryKey(['id']);
            $table->addIndex(['note_id'], 'prinotes_ver_note');
            $table->addIndex(['note_id', 'created_at'], 'prinotes_ver_note_date');
        }

        // ── Reminders ─────────────────────────────────────────────────────────
        if (!$schema->hasTable('prinotes_reminders')) {
            $table = $schema->createTable('prinotes_reminders');
            $table->addColumn('id', Types::BIGINT, ['autoincrement' => true, 'notnull' => true]);
            $table->addColumn('note_id', Types::BIGINT, ['notnull' => true]);
            $table->addColumn('user_id', Types::STRING, ['notnull' => true, 'length' => 64]);
            $table->addColumn('remind_at', Types::BIGINT, ['notnull' => true]);
            $table->addColumn('is_recurring', Types::SMALLINT, ['notnull' => true, 'default' => 0]);
            $table->addColumn('recurrence_rule', Types::STRING, ['notnull' => false, 'length' => 100, 'default' => null]);
            $table->addColumn('is_sent', Types::SMALLINT, ['notnull' => true, 'default' => 0]);
            $table->addColumn('created_at', Types::BIGINT, ['notnull' => true, 'default' => 0]);
            $table->setPrimaryKey(['id']);
            $table->addIndex(['note_id'], 'prinotes_rem_note');
            $table->addIndex(['user_id', 'remind_at', 'is_sent'], 'prinotes_rem_due');
        }

        // ── Shares ────────────────────────────────────────────────────────────
        if (!$schema->hasTable('prinotes_shares')) {
            $table = $schema->createTable('prinotes_shares');
            $table->addColumn('id', Types::BIGINT, ['autoincrement' => true, 'notnull' => true]);
            $table->addColumn('note_id', Types::BIGINT, ['notnull' => true]);
            $table->addColumn('owner_id', Types::STRING, ['notnull' => true, 'length' => 64]);
            $table->addColumn('share_type', Types::STRING, ['notnull' => true, 'length' => 16]); // 'user' | 'public'
            $table->addColumn('shared_with', Types::STRING, ['notnull' => false, 'length' => 64, 'default' => null]);
            $table->addColumn('token', Types::STRING, ['notnull' => false, 'length' => 64, 'default' => null]);
            $table->addColumn('permissions', Types::STRING, ['notnull' => true, 'length' => 16, 'default' => 'read']); // 'read' | 'write'
            $table->addColumn('created_at', Types::BIGINT, ['notnull' => true, 'default' => 0]);
            $table->setPrimaryKey(['id']);
            $table->addIndex(['note_id'], 'prinotes_sh_note');
            $table->addIndex(['token'], 'prinotes_sh_token');
            $table->addIndex(['shared_with'], 'prinotes_sh_with');
        }

        // ── Settings ──────────────────────────────────────────────────────────
        if (!$schema->hasTable('prinotes_settings')) {
            $table = $schema->createTable('prinotes_settings');
            $table->addColumn('id', Types::BIGINT, ['autoincrement' => true, 'notnull' => true]);
            $table->addColumn('user_id', Types::STRING, ['notnull' => true, 'length' => 64]);
            $table->addColumn('key', Types::STRING, ['notnull' => true, 'length' => 100]);
            $table->addColumn('value', Types::TEXT, ['notnull' => false, 'default' => null]);
            $table->setPrimaryKey(['id']);
            $table->addUniqueIndex(['user_id', 'key'], 'prinotes_set_unique');
        }

        // ── Attachments ───────────────────────────────────────────────────────
        if (!$schema->hasTable('prinotes_attachments')) {
            $table = $schema->createTable('prinotes_attachments');
            $table->addColumn('id', Types::BIGINT, ['autoincrement' => true, 'notnull' => true]);
            $table->addColumn('note_id', Types::BIGINT, ['notnull' => true]);
            $table->addColumn('user_id', Types::STRING, ['notnull' => true, 'length' => 64]);
            $table->addColumn('filename', Types::STRING, ['notnull' => true, 'length' => 500]);
            $table->addColumn('mime_type', Types::STRING, ['notnull' => true, 'length' => 100]);
            $table->addColumn('size', Types::BIGINT, ['notnull' => true, 'default' => 0]);
            $table->addColumn('nc_file_id', Types::BIGINT, ['notnull' => false, 'default' => null]);
            $table->addColumn('created_at', Types::BIGINT, ['notnull' => true, 'default' => 0]);
            $table->setPrimaryKey(['id']);
            $table->addIndex(['note_id'], 'prinotes_att_note');
            $table->addIndex(['user_id'], 'prinotes_att_user');
        }

        return $schema;
    }
}
