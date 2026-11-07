# Changelog

All notable changes to PriNotes are documented here.

## [1.2.1] – 2026-11-07

### Added
- **To-Do lists** (web and Android), in the side menu above Trash. Categories with sub-categories, smart lists (Today, Important, Planned, All tasks), due dates, reminders, repeating tasks (daily, weekdays, weekly, monthly, yearly), steps, notes and a star for important tasks. Finished tasks collapse into a "Finished" group under the same category.
- To-Dos use the same sync as notes (`/api/sync/pull` and `/api/sync/push`), so web and phone stay in step. The server creates the next occurrence of a repeating task when it is completed.
- Reminders: Nextcloud notification from a background job (every minute), and local alarms with Done / Snooze actions on Android.
- Android home-screen widgets (medium and large) that show to-dos from any mix of lists, let you tick tasks and add new ones.
- Android: bulk select (long-press), bulk finish and bulk delete with Undo, and a compact "Add a task" bar like Microsoft To-Do.

### Changed
- Database: two new tables, `prinotes_todo_lists` and `prinotes_todos` (additive migration; existing notes are untouched).

### Fixed
- Check circles in the To-Do list were stretched into ovals by Nextcloud's default button sizing.

## [1.1.3] – 2026-10-11

### Fixed
- Sharing a note failed with HTTP 500 on PostgreSQL (`null value in column "share_type"`). `Share::$shareType` defaulted to `'user'`, so Nextcloud's `Entity::setter()` treated `setShareType('user')` as unchanged and left the column out of the INSERT. Defaults are now `null` so the value is always written. (#2)

## [1.0.3] – 2026-08-10

### Fixed
- App store release signing used the wrong RSA padding scheme (PKCS1v15 instead of PSS with SHA-1 digest / SHA-512 MGF1, salt length 0), causing every published release to fail Nextcloud's code signature check with `InvalidSignatureException: Signature could not get verified.`. Releases are now signed correctly.

## [1.0.0] – 2026-05-13

### Added
- Rich block editor: paragraphs, headings (H1–H3), lists, checklists, code blocks, quotes, dividers
- Full-canvas freehand drawing support with undo/redo
- Image attachments with inline resize and rotate
- Notebooks with colour coding and drag-to-reorder
- Tags with colour labels; multi-tag support per note
- Pin notes to top of list
- Per-note colour theming
- Full-text search (title, preview, content)
- Archive and Trash with restore and permanent delete
- Per-note PIN lock (content hidden from search and previews when locked)
- App-wide PIN lock + biometric unlock (Android)
- Hidden notes vault — notes revealed only by typing a secret vault password in search
- Android offline-first client with automatic background sync (every 60 s)
- Grid and list view with persistent preference
- Dark / light / system theme (web + Android)
- Nextcloud 25–33 compatibility
