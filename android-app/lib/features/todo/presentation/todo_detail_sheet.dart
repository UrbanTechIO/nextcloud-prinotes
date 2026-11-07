import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/local/database.dart';
import '../data/todo_repository.dart';
import '../providers/todo_provider.dart';

Future<void> showTodoDetailSheet(BuildContext context, int todoId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _TodoDetail(todoId: todoId),
  );
}

class _TodoDetail extends ConsumerStatefulWidget {
  final int todoId;
  const _TodoDetail({required this.todoId});
  @override
  ConsumerState<_TodoDetail> createState() => _TodoDetailState();
}

class _TodoDetailState extends ConsumerState<_TodoDetail> {
  late final TextEditingController _title;
  late final TextEditingController _note;
  final _newStep = TextEditingController();
  bool _loaded = false;

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _newStep.dispose();
    super.dispose();
  }

  TodoRepository get _repo => ref.read(todoRepositoryProvider);

  Future<void> _pickDue(Todo t) async {
    final initial = t.dueDate != null ? DateTime.tryParse(t.dueDate!) ?? DateTime.now() : DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null) await _repo.updateTodo(t.id, TodosCompanion(dueDate: Value(localDateString(d))));
  }

  Future<void> _pickRemind(Todo t) async {
    final base = t.remindAt != null ? DateTime.fromMillisecondsSinceEpoch(t.remindAt! * 1000) : DateTime.now().add(const Duration(hours: 1));
    final d = await showDatePicker(context: context, initialDate: base, firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (d == null || !mounted) return;
    final tm = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(base));
    if (tm == null) return;
    final when = DateTime(d.year, d.month, d.day, tm.hour, tm.minute);
    await _repo.updateTodo(t.id, TodosCompanion(
      remindAt: Value(when.millisecondsSinceEpoch ~/ 1000),
      reminderSent: const Value(false),
    ));
  }

  String _remindText(int s) {
    final d = DateTime.fromMillisecondsSinceEpoch(s * 1000);
    final two = (int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}  ${two(d.hour)}:${two(d.minute)}';
  }

  Future<void> _saveSteps(Todo t, List<TodoStep> steps) =>
      _repo.updateTodo(t.id, TodosCompanion(steps: Value(TodoStep.encode(steps))));

  @override
  Widget build(BuildContext context) {
    final todos = ref.watch(todosProvider).valueOrNull ?? [];
    final lists = ref.watch(todoListsProvider).valueOrNull ?? [];
    final t = todos.where((x) => x.id == widget.todoId).firstOrNull;
    // The task vanished (deleted here or by a sync): show nothing while the sheet closes.
    if (t == null) return const SizedBox(height: 120);

    if (!_loaded) {
      _title = TextEditingController(text: t.title);
      _note = TextEditingController(text: t.note ?? '');
      _loaded = true;
    }
    final steps = TodoStep.decode(t.steps);
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(listPath(lists, t.listLocalId), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12))),
            IconButton(
              icon: Icon(t.isImportant ? Icons.star_rounded : Icons.star_border_rounded, color: t.isImportant ? Colors.amber : null),
              onPressed: () => _repo.updateTodo(t.id, TodosCompanion(isImportant: Value(!t.isImportant))),
            ),
          ]),
          Row(children: [
            Checkbox(shape: const CircleBorder(), value: t.isDone, onChanged: (_) => _repo.toggleDone(t.id)),
            Expanded(
              child: TextField(
                controller: _title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                decoration: const InputDecoration(border: InputBorder.none, hintText: 'Task title'),
                onSubmitted: (v) => _saveTitle(t, v),
                onTapOutside: (_) => _saveTitle(t, _title.text),
              ),
            ),
          ]),
          const Divider(),
          for (final s in steps)
            Row(children: [
              Checkbox(
                shape: const CircleBorder(),
                visualDensity: VisualDensity.compact,
                value: s.done,
                onChanged: (_) => _saveSteps(t, [for (final x in steps) x.id == s.id ? TodoStep(x.id, x.text, !x.done) : x]),
              ),
              Expanded(child: Text(s.text, style: TextStyle(decoration: s.done ? TextDecoration.lineThrough : null))),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => _saveSteps(t, steps.where((x) => x.id != s.id).toList()),
              ),
            ]),
          TextField(
            controller: _newStep,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.add), hintText: 'Add step', border: InputBorder.none),
            onSubmitted: (v) async {
              final text = v.trim();
              if (text.isEmpty) return;
              await _saveSteps(t, [...steps, TodoStep('s${DateTime.now().microsecondsSinceEpoch}', text, false)]);
              _newStep.clear();
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.event_outlined),
            title: Text(t.dueDate ?? 'Add due date'),
            trailing: t.dueDate != null
                ? IconButton(icon: const Icon(Icons.close), onPressed: () => _repo.updateTodo(t.id, const TodosCompanion(dueDate: Value(null))))
                : null,
            onTap: () => _pickDue(t),
          ),
          ListTile(
            leading: const Icon(Icons.notifications_none_rounded),
            title: Text(t.remindAt != null ? _remindText(t.remindAt!) : 'Remind me'),
            trailing: t.remindAt != null
                ? IconButton(icon: const Icon(Icons.close), onPressed: () => _repo.updateTodo(t.id, const TodosCompanion(remindAt: Value(null))))
                : null,
            onTap: () => _pickRemind(t),
          ),
          ListTile(
            leading: const Icon(Icons.repeat_rounded),
            title: DropdownButton<String?>(
              value: t.repeatRule,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: null, child: Text('Does not repeat')),
                DropdownMenuItem(value: 'daily', child: Text('Daily')),
                DropdownMenuItem(value: 'weekdays', child: Text('Weekdays')),
                DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                DropdownMenuItem(value: 'yearly', child: Text('Yearly')),
              ],
              onChanged: (v) => _repo.updateTodo(t.id, TodosCompanion(repeatRule: Value(v))),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: DropdownButton<int>(
              value: lists.any((l) => l.id == t.listLocalId) ? t.listLocalId : null,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              items: [for (final l in lists) DropdownMenuItem(value: l.id, child: Text(listPath(lists, l.id)))],
              onChanged: (v) => v == null ? null : _repo.updateTodo(t.id, TodosCompanion(listLocalId: Value(v))),
            ),
          ),
          const Divider(),
          TextField(
            controller: _note,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(hintText: 'Add a note…', prefixIcon: Icon(Icons.notes_rounded)),
            onTapOutside: (_) => _saveNote(t, _note.text),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              label: const Text('Delete task', style: TextStyle(color: Colors.redAccent)),
              onPressed: () async {
                final repo = _repo;
                final messenger = ScaffoldMessenger.of(context);
                // Close first so the sheet never redraws for a task that no longer exists.
                Navigator.of(context).pop();
                final snap = await repo.deleteTodo(t.id);
                if (snap == null) return;
                messenger.showSnackBar(SnackBar(
                  content: const Text('Task deleted'),
                  action: SnackBarAction(label: 'Undo', onPressed: () => repo.restoreTodo(snap)),
                ));
              },
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _saveTitle(Todo t, String v) async {
    final s = v.trim();
    if (s.isEmpty) {
      _title.text = t.title;
      return;
    }
    if (s != t.title) await _repo.updateTodo(t.id, TodosCompanion(title: Value(s)));
  }

  Future<void> _saveNote(Todo t, String v) async {
    if (v != (t.note ?? '')) await _repo.updateTodo(t.id, TodosCompanion(note: Value(v.isEmpty ? null : v)));
  }
}
