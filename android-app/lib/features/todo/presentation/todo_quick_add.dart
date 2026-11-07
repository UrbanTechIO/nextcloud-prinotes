import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/local/database.dart';
import '../data/todo_repository.dart';
import '../providers/todo_provider.dart';

/// Microsoft To-Do style composer: a slim bar above the keyboard, the list stays visible behind it.
/// It stays open after "send" so several tasks can be typed in a row; back or a tap outside closes it.
Future<void> showTodoQuickAdd(BuildContext context, {required List<TodoList> lists, required TodoViewSel view}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    barrierColor: Colors.black26,
    builder: (_) => _QuickAddBar(lists: lists, view: view),
  );
}

class _QuickAddBar extends ConsumerStatefulWidget {
  final List<TodoList> lists;
  final TodoViewSel view;
  const _QuickAddBar({required this.lists, required this.view});
  @override
  ConsumerState<_QuickAddBar> createState() => _QuickAddBarState();
}

class _QuickAddBarState extends ConsumerState<_QuickAddBar> {
  final _title = TextEditingController();
  final _focus = FocusNode();
  late int? _listId;
  String? _due;
  int? _remind;
  String? _repeat;
  late bool _star;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _listId = widget.view.listId ?? widget.lists.where((l) => l.isSystem).firstOrNull?.id;
    _due = widget.view.smart == 'today' ? localDateString() : null;
    _star = widget.view.smart == 'important';
    _title.addListener(() {
      final has = _title.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _title.text.trim();
    if (text.isEmpty) return;
    final repo = ref.read(todoRepositoryProvider);
    // Capture, then reset the bar right away so it is ready for the next task.
    final listId = _listId, remind = _remind, repeat = _repeat, star = _star;
    // A repeating task needs a date to repeat from.
    final due = _due ?? (repeat != null ? localDateString() : null);
    _title.clear();
    setState(() {
      _due = widget.view.smart == 'today' ? localDateString() : null;
      _remind = null;
      _repeat = null;
      _star = widget.view.smart == 'important';
    });
    _focus.requestFocus();
    try {
      await repo.addTodo(text, listLocalId: listId, dueDate: due, remindAt: remind, repeatRule: repeat, important: star);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not add the task')));
      }
    }
  }

  DateTime _atNine(DateTime d) => DateTime(d.year, d.month, d.day, 9);

  Future<DateTime?> _pickDateTime() async {
    final d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (d == null || !mounted) return null;
    final tm = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (tm == null) return null;
    return DateTime(d.year, d.month, d.day, tm.hour, tm.minute);
  }

  String _dueLabel(String d) {
    final now = DateTime.now();
    if (d == localDateString(now)) return 'Today';
    if (d == localDateString(now.add(const Duration(days: 1)))) return 'Tomorrow';
    return d;
  }

  String _remindLabel(int s) {
    final d = DateTime.fromMillisecondsSinceEpoch(s * 1000);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
  }

  Widget _chip(IconData icon, String label, {bool active = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: active ? scheme.primary.withValues(alpha: 0.15) : null,
        border: Border.all(color: active ? scheme.primary : scheme.outlineVariant),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: active ? scheme.primary : scheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 13, color: active ? scheme.primary : scheme.onSurface)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lists = widget.lists;
    final listName = lists.where((l) => l.id == _listId).firstOrNull;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
          child: Row(children: [
            Icon(Icons.radio_button_unchecked, color: scheme.outline),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _title,
                focusNode: _focus,
                autofocus: true,
                textInputAction: TextInputAction.send,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(border: InputBorder.none, hintText: 'Add a task', isDense: true),
                onSubmitted: (_) => _send(),
              ),
            ),
            IconButton.filled(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.arrow_upward_rounded),
              onPressed: _hasText ? _send : null,
            ),
          ]),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Row(children: [
            PopupMenuButton<int>(
              tooltip: 'Category',
              onSelected: (v) => setState(() => _listId = v),
              itemBuilder: (_) => [for (final l in lists) PopupMenuItem(value: l.id, child: Text(listPath(lists, l.id)))],
              child: _chip(Icons.folder_outlined, listName?.title ?? 'Category'),
            ),
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              tooltip: 'Due date',
              onSelected: (v) async {
                final now = DateTime.now();
                if (v == 'today') setState(() => _due = localDateString(now));
                if (v == 'tomorrow') setState(() => _due = localDateString(now.add(const Duration(days: 1))));
                if (v == 'nextweek') setState(() => _due = localDateString(now.add(Duration(days: 8 - now.weekday))));
                if (v == 'clear') setState(() => _due = null);
                if (v == 'pick') {
                  final d = await showDatePicker(context: context, initialDate: now, firstDate: DateTime(2020), lastDate: DateTime(2100));
                  if (d != null) setState(() => _due = localDateString(d));
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'today', child: Text('Today')),
                const PopupMenuItem(value: 'tomorrow', child: Text('Tomorrow')),
                const PopupMenuItem(value: 'nextweek', child: Text('Next week')),
                const PopupMenuItem(value: 'pick', child: Text('Pick a date')),
                if (_due != null) const PopupMenuItem(value: 'clear', child: Text('No due date')),
              ],
              child: _chip(Icons.event_outlined, _due == null ? 'Set due date' : _dueLabel(_due!), active: _due != null),
            ),
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              tooltip: 'Remind me',
              onSelected: (v) async {
                final now = DateTime.now();
                DateTime? when;
                if (v == 'later') when = now.add(const Duration(hours: 3));
                if (v == 'tomorrow') when = _atNine(now.add(const Duration(days: 1)));
                if (v == 'nextweek') when = _atNine(now.add(Duration(days: 8 - now.weekday)));
                if (v == 'pick') when = await _pickDateTime();
                if (v == 'clear') {
                  setState(() => _remind = null);
                  return;
                }
                if (when != null) setState(() => _remind = when!.millisecondsSinceEpoch ~/ 1000);
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'later', child: Text('Later today (in 3 h)')),
                const PopupMenuItem(value: 'tomorrow', child: Text('Tomorrow 9:00')),
                const PopupMenuItem(value: 'nextweek', child: Text('Next week 9:00')),
                const PopupMenuItem(value: 'pick', child: Text('Pick date & time')),
                if (_remind != null) const PopupMenuItem(value: 'clear', child: Text('No reminder')),
              ],
              child: _chip(Icons.notifications_none_rounded, _remind == null ? 'Remind me' : _remindLabel(_remind!), active: _remind != null),
            ),
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              tooltip: 'Repeat',
              onSelected: (v) => setState(() => _repeat = v == 'none' ? null : v),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'daily', child: Text('Daily')),
                const PopupMenuItem(value: 'weekdays', child: Text('Weekdays')),
                const PopupMenuItem(value: 'weekly', child: Text('Weekly')),
                const PopupMenuItem(value: 'monthly', child: Text('Monthly')),
                const PopupMenuItem(value: 'yearly', child: Text('Yearly')),
                if (_repeat != null) const PopupMenuItem(value: 'none', child: Text('Does not repeat')),
              ],
              child: _chip(Icons.repeat_rounded, _repeat == null ? 'Repeat' : _repeat![0].toUpperCase() + _repeat!.substring(1), active: _repeat != null),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => setState(() => _star = !_star),
              child: _chip(_star ? Icons.star_rounded : Icons.star_border_rounded, 'Important', active: _star),
            ),
          ]),
        ),
      ]),
    );
  }
}
