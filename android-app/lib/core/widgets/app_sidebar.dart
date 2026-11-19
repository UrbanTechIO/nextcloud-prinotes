import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../theme/glass.dart';

/// Which part of the app a sidebar belongs to; the switch at its top moves between them.
enum SidebarMode { notes, todo }

/// Sidebar width: 80% of the screen, but never narrower than 272 dp or wider than 320 dp, so it is a
/// comfortable side panel on small phones, large phones, tablets and in landscape.
double sidebarWidth(double screenWidth) => (screenWidth * 0.8).clamp(272.0, 320.0).toDouble();

/// Below this height (dp) the bottom bar scrolls with the list instead of staying pinned.
const double kSidebarTallHeight = 500;

class SidebarBarItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  /// A number shown on the icon when above zero (for example the notes in the trash).
  final int count;
  const SidebarBarItem(this.icon, this.label, this.onTap, {this.count = 0});
}

/// The shared sidebar frame: account header, Notes / To-Do switch, [content], and a bottom bar.
/// On a tall screen the header and bar stay put and the middle scrolls; on a short one everything
/// scrolls as one list so nothing is cut off.
class AppSidebar extends ConsumerWidget {
  final SidebarMode mode;
  final VoidCallback onNotes;
  final VoidCallback onTodo;
  final List<Widget> content;
  final List<SidebarBarItem> bar;

  const AppSidebar({
    super.key,
    required this.mode,
    required this.onNotes,
    required this.onTodo,
    required this.content,
    required this.bar,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final glass = ref.watch(glassProvider);
    final auth = ref.watch(authStateProvider);
    final size = MediaQuery.sizeOf(context);
    final tall = size.height >= kSidebarTallHeight;

    final header = Column(mainAxisSize: MainAxisSize.min, children: [
      DrawerAccountHeader(
        name: auth.username ?? 'PriNotes',
        subtitle: auth.serverUrl ?? '',
        icon: mode == SidebarMode.todo ? Icons.task_alt_rounded : Icons.note_alt_rounded,
      ),
      SidebarModeSwitch(mode: mode, onNotes: onNotes, onTodo: onTodo),
    ]);
    final bottom = SidebarBar(items: bar);

    final body = tall
        ? Column(children: [
            header,
            Expanded(child: ListView(padding: EdgeInsets.zero, children: content)),
            bottom,
          ])
        : ListView(padding: EdgeInsets.zero, children: [header, ...content, bottom]);

    return Drawer(
      elevation: glass.glass ? 0 : null,
      width: sidebarWidth(size.width),
      child: GlassDrawerBody(child: body),
    );
  }
}

class SidebarModeSwitch extends StatelessWidget {
  final SidebarMode mode;
  final VoidCallback onNotes;
  final VoidCallback onTodo;
  const SidebarModeSwitch({super.key, required this.mode, required this.onNotes, required this.onTodo});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget seg(String label, bool active, VoidCallback onTap) => Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: active ? null : onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: active ? scheme.onSurface.withOpacity(0.16) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Text(label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                    color: active ? scheme.onSurface : scheme.onSurface.withOpacity(0.6),
                  )),
            ),
          ),
        );
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: scheme.onSurface.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        seg('Notes', mode == SidebarMode.notes, onNotes),
        seg('To-Do', mode == SidebarMode.todo, onTodo),
      ]),
    );
  }
}

/// A big rounded tile: an icon, an optional count and a label.
class SidebarTile extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String label;
  final int? count;
  final bool selected;
  final VoidCallback onTap;
  const SidebarTile({
    super.key,
    required this.icon,
    this.iconColor,
    required this.label,
    this.count,
    this.selected = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primary.withOpacity(0.24) : scheme.onSurface.withOpacity(0.08),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 20, color: iconColor ?? scheme.onSurface.withOpacity(0.75)),
            if (count != null) Text('$count', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500, height: 1.25)),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: scheme.onSurface.withOpacity(0.7))),
          ]),
        ),
      ),
    );
  }
}

/// Lays tiles out in two equal columns; heights follow the text size.
class SidebarTileGrid extends StatelessWidget {
  final List<Widget> tiles;
  const SidebarTileGrid({super.key, required this.tiles});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: LayoutBuilder(builder: (_, c) {
          final w = (c.maxWidth - 8) / 2;
          return Wrap(spacing: 8, runSpacing: 8, children: [for (final t in tiles) SizedBox(width: w, child: t)]);
        }),
      );
}

class SidebarSection extends StatelessWidget {
  final String label;
  final VoidCallback? onAdd;
  const SidebarSection(this.label, {super.key, this.onAdd});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withOpacity(0.55);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 14, onAdd == null ? 16 : 6, 2),
      child: Row(children: [
        Expanded(
          child: Text(label.toUpperCase(),
              style: TextStyle(fontSize: 11, letterSpacing: 1.0, fontWeight: FontWeight.w600, color: muted)),
        ),
        if (onAdd != null)
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.add, size: 20, color: muted),
            tooltip: 'New',
            onPressed: onAdd,
          ),
      ]),
    );
  }
}

/// One compact row: a coloured dot or icon, a one-line name, and an optional count.
class SidebarRow extends StatelessWidget {
  final Widget? leading;
  final Widget title;
  final int? count;
  final bool selected;
  final double indent;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  const SidebarRow({
    super.key,
    this.leading,
    required this.title,
    this.count,
    this.selected = false,
    this.indent = 0,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Material(
        color: selected ? scheme.primary.withOpacity(0.2) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          onLongPress: onLongPress,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Padding(
              padding: EdgeInsets.fromLTRB(8 + indent, 4, 10, 4),
              child: Row(children: [
                if (leading != null) ...[leading!, const SizedBox(width: 10)],
                Expanded(child: title),
                if (count != null)
                  Text('$count',
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurface.withOpacity(count == 0 ? 0.4 : 0.75),
                      )),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class SidebarDot extends StatelessWidget {
  final Color color;
  const SidebarDot(this.color, {super.key});
  @override
  Widget build(BuildContext context) =>
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}

/// A small pill, used for tags.
class SidebarChip extends StatelessWidget {
  final String label;
  final Color? color;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  const SidebarChip({super.key, required this.label, this.color, this.selected = false, required this.onTap, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = color ?? scheme.onSurface.withOpacity(0.6);
    return Material(
      color: selected ? c.withOpacity(0.35) : scheme.onSurface.withOpacity(0.08),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            SidebarDot(c),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 13)),
          ]),
        ),
      ),
    );
  }
}

class SidebarBar extends StatelessWidget {
  final List<SidebarBarItem> items;
  const SidebarBar({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: scheme.onSurface.withOpacity(0.15)))),
      child: SafeArea(
        top: false,
        child: Row(children: [
          for (final i in items)
            Expanded(
              child: InkWell(
                onTap: i.onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Badge(
                      isLabelVisible: i.count > 0,
                      label: Text('${i.count}'),
                      child: Icon(i.icon, size: 22, color: scheme.onSurface.withOpacity(0.75)),
                    ),
                    const SizedBox(height: 2),
                    Text(i.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: scheme.onSurface.withOpacity(0.7))),
                  ]),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

class SidebarAction {
  final IconData icon;
  final String label;
  final bool danger;
  final VoidCallback onTap;
  const SidebarAction(this.icon, this.label, this.onTap, {this.danger = false});
}

/// A small bottom sheet of actions, opened by long-pressing a sidebar row.
Future<void> showSidebarActions(BuildContext context, {required String title, required List<SidebarAction> actions}) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        for (final a in actions)
          ListTile(
            leading: Icon(a.icon, color: a.danger ? Colors.redAccent : null),
            title: Text(a.label, style: TextStyle(color: a.danger ? Colors.redAccent : null)),
            onTap: () {
              Navigator.pop(ctx);
              a.onTap();
            },
          ),
      ]),
    ),
  );
}
