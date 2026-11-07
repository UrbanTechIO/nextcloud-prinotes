# PriNotes To-Do: how to use it efficiently

This guide covers the To-Do feature on the web app and on Android. Both use the same sync as notes, so a task you create on one shows on the other within moments.

## 1. The mental model

- **Inbox** is the default list. Anything you add without choosing a category lands there. It cannot be renamed, moved or deleted.
- **Categories** are your own lists, for example `Home Assistant`. A category can have **sub-categories** one level deep, for example `Home Assistant > Cards`, `Automations`, `Scripts`.
- **Smart lists** are views, not folders. A task lives in exactly one category and can appear in several smart lists:
  - **Today**: due today, plus anything overdue.
  - **Important**: tasks you starred.
  - **Planned**: anything that has a due date.
  - **All tasks**: everything open.
- Opening a category also shows the tasks of its sub-categories, with a small path label (`Parent › Child`) so you can tell them apart.
- **Finished** tasks move into a collapsible *Finished (n)* group under the same list. In smart lists only the last 7 days of finished tasks are shown.

## 2. Fast capture (the habit that pays off)

Do not organise while capturing. Type the task, send it, move on. Sort it later.

**Web**
1. Open *To-Do* in the left menu (above Trash).
2. Click *Add a task…* at the bottom of the list, type, press Enter. The field stays ready for the next one.
3. Whichever list is open decides where the task goes. Open *Today* first and new tasks are due today. Open *Important* first and they are starred.

**Android**
1. Menu → *To-Do*, then tap **+**.
2. A slim bar opens above the keyboard. Type and tap the arrow. The bar stays open so you can add several tasks in a row. Press back to close it.
3. Under the text field are quick chips: **category**, **due date** (Today, Tomorrow, Next week, pick a date), **Remind me** (in 3 hours, tomorrow 9:00, next week 9:00, or pick), **Repeat**, and **Important**. They reset after each task, except the category, which stays so a run of related tasks is quick.

## 3. Planning a day in two minutes

1. Open **All tasks**. Star the 2 or 3 things that matter today.
2. Give them a due date of today (the due-date chip on Android, the detail panel on web).
3. Work from **Today**. It is your daily list, and yesterday's unfinished tasks appear there automatically as overdue (shown in red).
4. Tick tasks as you go. They drop into *Finished*, which is a quick record of what you did.

## 4. Reminders

- One reminder per task. Set it from the *Remind me* chip when adding, or from the task detail.
- **Web:** the server sends a Nextcloud notification (bell icon) at the reminder time. It checks every minute.
- **Android:** the phone schedules a local alarm, so it fires even when offline. The notification has two buttons:
  - **Done** marks the task finished.
  - **Snooze 1 h** moves the reminder one hour ahead.
- Android needs two permissions: notifications, and "alarms & reminders". If exact alarms are refused, reminders still fire but can be a few minutes late.
- Changing a task's reminder, or un-finishing a task, re-arms it.

## 5. Repeating tasks

Choose **Repeat**: daily, weekdays, weekly, monthly or yearly.

- A repeating task needs a due date. If you pick Repeat on Android without one, today is used.
- When you tick a repeating task done, the **server creates the next one** with the next due date (and the reminder shifted by the same amount). You never get duplicates, even if you complete it from the phone while offline and the web syncs later.
- Monthly and yearly clamp to the end of the month. A task due on the 31st next falls on the 28th/29th in February, then returns to the 31st where the month allows. Feb 29 repeats on Feb 28 in non-leap years.
- *Weekdays* skips Saturday and Sunday.

## 6. Steps, notes and structure

Open a task to get the detail view.
- **Steps** are a mini checklist inside a task (up to 100). Use them for anything that is one outcome with several parts, for example "Release v1.3" with steps for changelog, build, upload.
- **Note** holds anything longer than a title.
- **Category** can be changed here. This is the quickest way to triage Inbox: open each task and file it.
- Tapping the star toggles *Important*.

Tip: use a category per project or area, and sub-categories for the parts that you want to look at separately. Keep the tree shallow. If a sub-category has only one or two tasks, a step list inside one task is usually cleaner.

## 7. Bulk actions (Android)

- **Long-press** a task to start selecting. Tap others to add or remove them.
- The top bar then offers **Select all**, **Mark finished** (or reopen, if they were all finished already) and **Delete**.
- Bulk delete shows an **Undo** for a few seconds.
- Back or the X leaves selection mode.

Single task: **swipe left** to delete, with Undo.

## 8. Deleting and undoing

- Tasks have no trash. Deleting a task shows **Undo** for a few seconds on both web and Android. After that it is gone (and removed from the other device at the next sync).
- **Deleting a category** deletes its sub-categories and all their tasks. You are asked first, with the number of tasks that will go.

## 9. Home-screen widgets (Android)

Long-press the home screen → Widgets → *PriNotes* → pick **To-Do (medium)** (4×2) or **To-Do (large)** (4×4).

1. **Choose what it shows.** The picker is multi-select: tick any mix of Today, Important, Planned, All open and your categories. Tick *Include sub-categories* to cover children of a chosen category.
2. **Tick a task** in the widget to finish it. It updates right away and syncs in the background.
3. **Tap the header** to change what the widget shows later.
4. **Tap +** to add a task. If the widget shows exactly one list, the task goes there without asking. Otherwise a small dialog asks for the category and pre-selects the last one you used. *Due today* is pre-ticked when the widget shows Today.
5. **Tap a task** to open the To-Do screen.

Good combinations:
- A *Today + Important* widget on the first home screen for the daily view.
- A large widget on a single project category (with sub-categories on) as a project board.
- A small *Inbox* widget so capturing is one tap.

If you delete or rename a category a widget uses, the widget shows an empty state asking you to choose again. It never falls back to another list's tasks.

## 10. Keeping web and phone in step

- Both sync automatically. Open the To-Do screen and tap the sync icon (Android) to force it.
- If the phone is on a network that cannot reach your server (for example a country-blocked public Wi-Fi), nothing syncs until you switch networks or turn the VPN on. Tasks stay safe on the phone and upload when it can connect.
- If you change the same task on two devices before they sync, the version with the higher change count wins as a whole task. Edit a task on one device at a time to avoid surprises.

## 11. A routine that works

| When | Do |
|------|----|
| Any time | Capture into the open list or Inbox. Do not sort. |
| Morning (2 min) | Open *All tasks*, star 2–3, set due *Today*. Work from *Today*. |
| Evening (2 min) | Triage *Inbox*: open each task, give it a category, due date or delete it. Glance at *Finished* to see what got done. |
| Weekly (10 min) | Open *Planned* to see what is coming. Tidy categories. Clear what is no longer relevant. |

## 12. Troubleshooting

| Symptom | Cause and fix |
|---------|---------------|
| Phone tasks missing on web | Phone cannot reach the server (blocked network/VPN). Switch network, tap sync. |
| Reminder arrives late | Exact alarms not allowed. In Android settings allow *Alarms & reminders* for PriNotes. |
| No reminder at all | Notifications permission off, or battery optimisation is killing the app. |
| Check circles look like ovals on web | Stale browser cache after an update. Hard refresh with Ctrl+Shift+R. |
| Widget shows "choose again" | Its category was deleted or renamed. Tap the header and pick again. |
