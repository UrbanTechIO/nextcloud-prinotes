<?php

return [
    'routes' => [
        // Page (web app entry)
        ['name' => 'page#index', 'url' => '/', 'verb' => 'GET'],

        // Notes API
        ['name' => 'note_api#index',    'url' => '/api/notes',                  'verb' => 'GET'],
        ['name' => 'note_api#create',   'url' => '/api/notes',                  'verb' => 'POST'],
        ['name' => 'note_api#show',     'url' => '/api/notes/{id}',             'verb' => 'GET'],
        ['name' => 'note_api#update',   'url' => '/api/notes/{id}',             'verb' => 'PUT'],
        ['name' => 'note_api#destroy',  'url' => '/api/notes/{id}',             'verb' => 'DELETE'],
        ['name' => 'note_api#restore',  'url' => '/api/notes/{id}/restore',     'verb' => 'POST'],

        // Note versions
        ['name' => 'note_api#versions', 'url' => '/api/notes/{id}/versions',    'verb' => 'GET'],
        ['name' => 'note_api#restoreVersion', 'url' => '/api/notes/{id}/versions/{versionId}/restore', 'verb' => 'POST'],
        ['name' => 'note_api#deleteVersion', 'url' => '/api/notes/{id}/versions/{versionId}', 'verb' => 'DELETE'],

        // Notebooks API
        ['name' => 'notebook_api#index',   'url' => '/api/notebooks',           'verb' => 'GET'],
        ['name' => 'notebook_api#create',  'url' => '/api/notebooks',           'verb' => 'POST'],
        ['name' => 'notebook_api#show',    'url' => '/api/notebooks/{id}',      'verb' => 'GET'],
        ['name' => 'notebook_api#update',  'url' => '/api/notebooks/{id}',      'verb' => 'PUT'],
        ['name' => 'notebook_api#destroy', 'url' => '/api/notebooks/{id}',      'verb' => 'DELETE'],

        // Tags API
        ['name' => 'tag_api#index',   'url' => '/api/tags',                     'verb' => 'GET'],
        ['name' => 'tag_api#create',  'url' => '/api/tags',                     'verb' => 'POST'],
        ['name' => 'tag_api#update',  'url' => '/api/tags/{id}',                'verb' => 'PUT'],
        ['name' => 'tag_api#destroy', 'url' => '/api/tags/{id}',                'verb' => 'DELETE'],

        // Reminders API
        ['name' => 'reminder_api#index',   'url' => '/api/reminders',           'verb' => 'GET'],
        ['name' => 'reminder_api#create',  'url' => '/api/reminders',           'verb' => 'POST'],
        ['name' => 'reminder_api#update',  'url' => '/api/reminders/{id}',      'verb' => 'PUT'],
        ['name' => 'reminder_api#destroy', 'url' => '/api/reminders/{id}',      'verb' => 'DELETE'],

        // Share API
        ['name' => 'share_api#create',  'url' => '/api/notes/{noteId}/shares',          'verb' => 'POST'],
        ['name' => 'share_api#index',   'url' => '/api/notes/{noteId}/shares',          'verb' => 'GET'],
        ['name' => 'share_api#destroy', 'url' => '/api/notes/{noteId}/shares/{shareId}','verb' => 'DELETE'],

        // Public share view
        ['name' => 'share_api#view',    'url' => '/share/{token}',              'verb' => 'GET'],

        // Sync API
        ['name' => 'sync_api#pull',     'url' => '/api/sync/pull',              'verb' => 'GET'],
        ['name' => 'sync_api#push',     'url' => '/api/sync/push',              'verb' => 'POST'],

        // Settings API
        ['name' => 'settings_api#get',  'url' => '/api/settings',               'verb' => 'GET'],
        ['name' => 'settings_api#set',  'url' => '/api/settings',               'verb' => 'POST'],

        // Attachment upload
        ['name' => 'attachment_api#upload',  'url' => '/api/attachments',       'verb' => 'POST'],
        ['name' => 'attachment_api#show',    'url' => '/api/attachments/{id}',  'verb' => 'GET'],
        ['name' => 'attachment_api#destroy', 'url' => '/api/attachments/{id}',  'verb' => 'DELETE'],

        // Search
        ['name' => 'note_api#search',   'url' => '/api/search',                 'verb' => 'GET'],
    ],
];
