<?php

declare(strict_types=1);

namespace OCA\PriNotes\Service;

use OCA\PriNotes\Db\SettingMapper;

class SettingsService {
    // Default settings
    private const DEFAULTS = [
        'version_history_enabled' => 'true',
        'version_history_days'    => '30',
        'default_sort'            => 'updated_desc',
        'theme'                   => 'auto',
        'editor_font_size'        => '16',
        'auto_save_interval'      => '5',   // seconds
        'trash_auto_delete_days'  => '30',
    ];

    public function __construct(private SettingMapper $mapper) {}

    public function get(string $userId, string $key, ?string $default = null): ?string {
        $val = $this->mapper->get($userId, $key);
        if ($val !== null) return $val;
        return $default ?? (self::DEFAULTS[$key] ?? null);
    }

    public function getAll(string $userId): array {
        $stored = $this->mapper->getAll($userId);
        return array_merge(self::DEFAULTS, $stored);
    }

    public function set(string $userId, string $key, ?string $value): void {
        $this->mapper->set($userId, $key, $value);
    }

    public function setMany(string $userId, array $settings): void {
        foreach ($settings as $key => $value) {
            $this->mapper->set($userId, (string)$key, $value !== null ? (string)$value : null);
        }
    }
}
