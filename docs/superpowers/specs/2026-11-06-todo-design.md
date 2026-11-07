# PriNotes To-Do — design

Date: 2026-11-06. Status: draft for approval. Nothing is built yet.

## Intent

The owner keeps projects as nested lists (Home Assistant > Cards / Automations /
Scripts, Nextcloud > Prinotes) and wants a rich task manager inside PriNotes, close
to Microsoft To Do on Android, available on the Android app and the web app, saved
and synced the same way notes are. Tasks can have reminders. The Android home
screen gets widgets that show tasks, tick them off, and add new ones.

## Goals

- To-Do section on web and Android, reachable from the side menu / drawer, placed in
  the first block above Trash.
- Categories with one level of sub-categories. Colour dot per category.
- Tasks: title, done, due date, one reminder time, repeat, steps (mini checklist),
  free-text note, important star.
- Smart lists: Today, Important, Planned (has a due date), All open tasks. Computed
  on the client from the data, not stored.
- Finished tasks move into a collapsible "Finished (n)" group at the bottom of the
  same category. Collapsed by default on Android, expanded on web (my call).
- Same sync mechanism as notes: Android works offline, syncs through the existing
  pull/push API, web talks to the server directly. Version-based conflict
  resolution like notes.
- Reminders: Android local notification at the time set (works offline); web gets a
  Nextcloud notification from the server (cron). Both fire for the same task, so the
  server must not push a duplicate to the phone, see Reminders.
- Android widgets: any number of widgets, each with its own source (multi-select of
  smart lists and categories, "include sub-categories" switch). Medium (4x2) and
  large (4x4, with quick-add field). Tap box = complete, tap text = open in app,
  "+" = quick add into a category.
- Look: PriNotes' own theme on both sides (web: Nextcloud dark variables, blue
  `#0082c9`, 12px cards, nav pattern of Notebooks/Tags; Android: navy `#0F172A`,
  cards `#1E293B`, border `#334155`, blue `#2563EB`). The approved mockups are in
  `.superpowers/brainstorm/` (todo-themed, todo-finished-widget, todo-widget-config).

## Non-goals

- Sharing lists or tasks with other users, comments, assignments.
- Attachments on tasks, location reminders, calendar sync, drag-and-drop reorder
  (sort_order column is reserved, UI is not in v1).
- A Trash for tasks (my call): delete is immediate with an "Undo" snackbar.
- Changing anything about how notes are stored, synced or rendered.

## Anti-goals (a failure even if it technically works)

- Any change to existing note, notebook, tag, reminder tables or sync results for
  notes. The migration is additive only.
- Notes sync getting slower or failing because the to-do part errors. To-do sync
  failures must be isolated like tag push failure already is.
- Duplicate reminders (phone and server both alerting the same device).
- Widget that shows stale ticks after the user completed something.

## Data model (server, new tables, new migration `Version002`)

`prinotes_todo_lists`: id, user_id, parent_id (null = top level; only one level
allowed, enforced in the service), title, color, sort_order, is_system (Inbox),
created_at, updated_at.

`prinotes_todos`: id, user_id, list_id (null not allowed, defaults to Inbox),
title, note (text), is_done, done_at, due_date (text `YYYY-MM-DD`, null, timezone-free),
remind_at (unix, null), next_spawned (bool),
reminder_sent (bool), repeat_rule (null | daily | weekdays | weekly | monthly |
yearly), is_important, steps (JSON text: `[{id,text,done}]`), sort_order,
created_at, updated_at, version.

Inbox: a system list created on first use per user, cannot be deleted or renamed.
Quick add from Today and from widgets with no single category goes there, with due
date today when added from Today.

Deleting a category deletes its tasks and sub-categories after a confirm dialog that
shows the count (my call).

Repeat: completing a repeating task marks it done and creates the next occurrence
(due and reminder moved forward), like Microsoft To Do. The new row is a normal
task, so sync needs nothing special.

## API

REST, same style and auth as the existing controllers: `/api/todo-lists` and
`/api/todos` (index, create, show, update, destroy).

Sync: extend `GET /api/sync/pull` with `todoLists` and `todos` (updated since
`since`, same semantics as notes) and `POST /api/sync/push` with `todoLists`,
`todos`, `deletedTodoIds`, `deletedTodoListIds`. Existing keys and behaviour stay
exactly as they are. Android pulls first, then pushes, as notes do. Conflict rule:
higher `version` wins; equal version with local pending change keeps local; same
rules as `_upsertNote`.

## Reminders

Server: a job (new, or the existing minute job extended) finds todos with
`remind_at <= now`, `reminder_sent = 0`, not done, and sends a Nextcloud
notification, then sets `reminder_sent`. Rendering needs a notification `Notifier`
class registered for the app (the existing `lib/Notification` folder is empty, so
check whether current note reminders render at all and reuse or fix).

Android: when a task with a reminder is synced or edited, schedule a local
notification (exact alarm, permission already declared), reschedule after reboot
(boot permission already declared), cancel on complete/delete. Notification tap
opens the task; action buttons "Done" and "Snooze 1 h" (my call).

Duplicate avoidance: the server notification goes to the web / Nextcloud clients;
the phone relies on its own local alarm. Whether the phone also shows the
Nextcloud push is the Nextcloud app's setting, not ours.

## Android

Drift schema 3 -> 4: add `TodoLists`, `Todos` tables (with `remoteId`, `isSynced`,
`hasLocalChanges`, `version`, same pattern as `Notes`); additive migration only.
Extend `SyncService` for to-dos; to-do errors must not abort the note sync.
New feature folder `lib/features/todo` (presentation, providers, data) following the
existing structure. Drawer entry "To-Do" above Trash, route `/todo`.

Widget: native Android `AppWidgetProvider` plus a Flutter bridge. Flutter cannot
draw a home-screen widget, so the visual part is native (RemoteViews list). The
builder picks the bridge (the `home_widget` package is the candidate). Requirements:

- Per-widget configuration (source multi-select, include-sub-categories) chosen when
  the widget is added and changeable from the header; stored per widget id.
- Widget reads from the local database snapshot, never needs the network to draw.
- Tapping a box completes the task immediately (optimistic update in the widget),
  then the app database is updated and a sync is triggered in the background.
- Quick add from "+": a small sheet asks title, category (pre-selected to the last
  used one; skipped when only one category is shown), optional due/reminder.
- Medium widget has no inline text field (RemoteViews cannot do reliable text input);
  the large one opens the same quick-add sheet from its "Add a task..." row.
  (my call: true inline typing is not possible in a widget, so the field is a button.)
- Overdue tasks first, then due time, then category; a task matching two sources
  appears once; Finished tasks are never shown.
- Theming matches the Android navy theme, light/dark follow the system.

## Web

New Vue views and a `todos` Pinia store next to `notes.js`, calling the REST API
directly. Sidebar: "To-Do" item in the first block above Trash plus a "TO-DO LISTS"
section (same component pattern as Notebooks/Tags: colour dots, counters, "+"),
smart lists on top, categories with nested sub-categories below. Task detail opens
in a right-hand panel or modal (builder's choice), with steps, note, due, reminder,
repeat. Debounced save like the note editor (10 s) is NOT used here: tasks save on
change (checkbox, field blur) because edits are small and the widget/phone should
see them quickly (my call).

## Rollout and safety

- Back up the database (dump) before running the migration on the production
  Nextcloud (192.168.0.3), as done on 2026-09-29.
- Web app and Android app are developed against the production server because that
  is the only server; the migration only adds tables, so existing notes are untouched.
- Server app version bump (1.2.0), Android app version bump; build the release APK
  (release builds only). Nothing is published to the App Store, GitHub release, or
  pushed to the repo until the owner has tried it and says so.

## Decisions made after review (my calls)

1. **Repeat, who creates the next task:** the server, once, when it receives a task
   whose `is_done` flips false -> true and `next_spawned` is false; it then sets
   `next_spawned`. Clients never create the next occurrence, so web, phone and widget
   cannot make duplicates. Offline on Android the task shows as done and the next
   occurrence appears after the next sync; completing from the app or widget
   triggers a sync right away, so the delay is normally seconds.
2. **Repeat dates:** `due_date` is a plain date with no timezone. "Today" and
   "overdue" are computed on the device from its local date. Repeat arithmetic works
   on the date (weekly = +7 days, monthly = same day next month, clamped to month
   end, weekdays = next Mon-Fri) and keeps the reminder's time of day. The server
   reminder job uses `remind_at` (unix), so it needs no timezone.
3. **Reminder reset:** the new occurrence starts with `reminder_sent = 0`. Editing
   `remind_at` or un-completing a task resets `reminder_sent` to 0. Android
   reschedules its alarm on every synced change to `remind_at`, `is_done` or delete.
4. **Note reminders:** a to-do `Notifier` is built separately. Existing note
   reminders are not touched. If they turn out to be broken, report it to the owner
   and do not fix it inside this project (anti-goal: no change to notes).
5. **Conflicts:** whole-row, higher `version` wins, same as notes. Steps are not
   merged. Accepted trade-off: a step tick on the phone can be lost if the web saves
   the same task from an older copy at about the same time.
6. **Deleting a category:** the server cascades (tasks and sub-categories). If a
   client later pushes a task whose category no longer exists, the server moves it
   to Inbox. Inbox is unique per user (unique index on `user_id` where
   `is_system = 1`); a second create returns the existing one.
7. **Widget writes:** native widget code never writes to the Drift SQLite file. It
   updates the widget snapshot immediately (optimistic) and queues the action
   (complete / add) for Flutter; a background Dart callback applies the queue to
   Drift and syncs. The snapshot is rebuilt from Drift after every applied queue.
8. **Exact alarms:** `SCHEDULE_EXACT_ALARM` (already declared). If the user has
   not granted it, fall back to an inexact alarm and show a one-time hint in
   Settings with a button to the system permission page.

## Left to the builder

Exact job structure for reminders, bridge package for the widget, config activity
implementation, detail-panel layout on web, icons, empty-state copy, drift
migration details, how counters are computed.
