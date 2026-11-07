import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/local/database.dart';
import '../providers/todo_provider.dart';

const todoColors = ['#ef4444', '#f97316', '#eab308', '#22c55e', '#2563eb', '#8b5cf6', '#ec4899', '#6b7280'];

Color todoColor(String? hex, [Color fallback = const Color(0xFF6B7280)]) {
  if (hex == null) return fallback;
  try {
    return Color(int.parse(hex.replaceAll('#', 'FF'), radix: 16));
  } catch (_) {
    return fallback;
  }
}

/// Create or edit a To-Do category. [parentLocalId] pre-selects a parent for new sub-categories.
Future<void> showTodoListDialog(BuildContext context, WidgetRef ref,
    {TodoList? list, int? parentLocalId}) async {
  final lists = ref.read(todoListsProvider).valueOrNull ?? [];
  final todos = ref.read(todosProvider).valueOrNull ?? [];
  final repo = ref.read(todoRepositoryProvider);
  final title = TextEditingController(text: list?.title ?? '');
  String? color = list?.color;
  int? parent = parentLocalId;
  String? error;
  final parents = lists.where((l) => l.parentLocalId == null && !l.isSystem && l.id != list?.id).toList();

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(list == null ? (parentLocalId != null ? 'New sub-category' : 'New category') : 'Edit category'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: title,
              autofocus: true,
              enabled: list?.isSystem != true,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            if (list == null && parentLocalId == null && parents.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                value: parent,
                decoration: const InputDecoration(labelText: 'Parent (optional)'),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('None (top level)')),
                  ...parents.map((p) => DropdownMenuItem<int?>(value: p.id, child: Text(p.title))),
                ],
                onChanged: (v) => setState(() => parent = v),
              ),
            ],
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in todoColors)
                GestureDetector(
                  onTap: () => setState(() => color = c),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: todoColor(c),
                      shape: BoxShape.circle,
                      border: Border.all(color: color == c ? Colors.white : Colors.transparent, width: 3),
                      boxShadow: color == c ? [BoxShadow(color: todoColor(c), blurRadius: 6)] : null,
                    ),
                  ),
                ),
              GestureDetector(
                onTap: () => setState(() => color = null),
                child: const CircleAvatar(radius: 15, backgroundColor: Colors.grey, child: Icon(Icons.close, size: 16)),
              ),
            ]),
            if (error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(error!, style: const TextStyle(color: Colors.redAccent))),
          ]),
        ),
        actions: [
          if (list != null && !list.isSystem)
            TextButton(
              onPressed: () async {
                final subs = lists.where((l) => l.parentLocalId == list.id).toList();
                final ids = {list.id, ...subs.map((s) => s.id)};
                final n = todos.where((t) => ids.contains(t.listLocalId)).length;
                final ok = await showDialog<bool>(
                  context: ctx,
                  builder: (c2) => AlertDialog(
                    title: Text('Delete "${list.title}"?'),
                    content: Text('This also deletes ${subs.isEmpty ? '' : '${subs.length} sub-categor${subs.length == 1 ? 'y' : 'ies'} and '}$n task${n == 1 ? '' : 's'}.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c2, false), child: const Text('Cancel')),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: Colors.red),
                        onPressed: () => Navigator.pop(c2, true),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  final view = ref.read(todoViewProvider);
                  if (view.listId != null && ids.contains(view.listId)) {
                    ref.read(todoViewProvider.notifier).state = const TodoViewSel.smart('today');
                  }
                  await repo.deleteList(list.id);
                  if (ctx.mounted) Navigator.pop(ctx);
                }
              },
              child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (title.text.trim().isEmpty) return;
              try {
                if (list == null) {
                  await repo.addList(title.text, parentLocalId: parent, color: color);
                } else {
                  await repo.updateList(list.id, title: title.text, color: color, clearColor: color == null);
                }
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                setState(() => error = e.toString().replaceFirst('Invalid argument(s): ', ''));
              }
            },
            child: Text(list == null ? 'Create' : 'Save'),
          ),
        ],
      ),
    ),
  );
}
