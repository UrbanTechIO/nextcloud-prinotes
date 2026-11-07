import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

/// The app's look: Classic (solid navy), Frosted Glass (blurred bar and cards) or
/// Liquid Glass (floating glass capsules). Modelled on UrbanChat's two glass themes.
enum ThemeStyle { classic, frosted, liquid }

class GlassSettings {
  static const defaultHeaderOpacity = 0.55;
  static const defaultCardOpacity = 0.35;

  final ThemeStyle style;
  final double headerOpacity;
  final double cardOpacity;

  /// Preset id from [kGlassBackgrounds], or 'custom' (the user's own image at [customPath]).
  final String background;
  final String? customPath;

  const GlassSettings({
    this.style = ThemeStyle.classic,
    this.headerOpacity = defaultHeaderOpacity,
    this.cardOpacity = defaultCardOpacity,
    this.background = 'aurora',
    this.customPath,
  });

  bool get glass => style != ThemeStyle.classic;
  bool get liquid => style == ThemeStyle.liquid;

  GlassSettings copyWith({
    ThemeStyle? style,
    double? headerOpacity,
    double? cardOpacity,
    String? background,
    String? customPath,
  }) =>
      GlassSettings(
        style: style ?? this.style,
        headerOpacity: (headerOpacity ?? this.headerOpacity).clamp(0.0, 1.0).toDouble(),
        cardOpacity: (cardOpacity ?? this.cardOpacity).clamp(0.0, 1.0).toDouble(),
        background: background ?? this.background,
        customPath: customPath ?? this.customPath,
      );

  static GlassSettings fromStored({
    String? style,
    String? header,
    String? card,
    String? background,
    String? customPath,
  }) {
    final s = ThemeStyle.values.where((v) => v.name == style).firstOrNull ?? ThemeStyle.classic;
    final path = (customPath == null || customPath.isEmpty) ? null : customPath;
    var bg = 'aurora';
    if (background == 'custom' && path != null) {
      bg = 'custom';
    } else if (kGlassBackgrounds.any((b) => b.id == background)) {
      bg = background!;
    }
    return GlassSettings(
      style: s,
      headerOpacity: (double.tryParse(header ?? '') ?? defaultHeaderOpacity).clamp(0.0, 1.0).toDouble(),
      cardOpacity: (double.tryParse(card ?? '') ?? defaultCardOpacity).clamp(0.0, 1.0).toDouble(),
      background: bg,
      customPath: path,
    );
  }
}

const _storage = FlutterSecureStorage();
const _kStyle = 'theme_style';
const _kHeader = 'glass_header_opacity';
const _kCard = 'glass_card_opacity';
const _kBg = 'glass_background';
const _kBgPath = 'glass_background_path';

Future<GlassSettings> loadGlassSettings() async {
  try {
    return GlassSettings.fromStored(
      style: await _storage.read(key: _kStyle),
      header: await _storage.read(key: _kHeader),
      card: await _storage.read(key: _kCard),
      background: await _storage.read(key: _kBg),
      customPath: await _storage.read(key: _kBgPath),
    );
  } catch (_) {
    return const GlassSettings();
  }
}

class GlassNotifier extends StateNotifier<GlassSettings> {
  GlassNotifier(super.state);

  Future<void> setStyle(ThemeStyle s) async {
    state = state.copyWith(style: s);
    await save();
  }

  Future<void> setPreset(String id) async {
    state = state.copyWith(background: id);
    await save();
  }

  /// Copies the picked image into app storage (the picker's temp file can vanish) and selects it.
  Future<void> setCustomImage(String sourcePath) async {
    final dir = await getApplicationSupportDirectory();
    final dest = File('${dir.path}/glass_bg_${DateTime.now().millisecondsSinceEpoch}.jpg');
    await File(sourcePath).copy(dest.path);
    final old = state.customPath;
    state = state.copyWith(background: 'custom', customPath: dest.path);
    await save();
    if (old != null && old != dest.path) {
      try {
        await File(old).delete();
      } catch (_) {}
    }
  }

  void setHeaderOpacity(double v) => state = state.copyWith(headerOpacity: v);
  void setCardOpacity(double v) => state = state.copyWith(cardOpacity: v);

  Future<void> save() async {
    try {
      await _storage.write(key: _kStyle, value: state.style.name);
      await _storage.write(key: _kHeader, value: state.headerOpacity.toStringAsFixed(2));
      await _storage.write(key: _kCard, value: state.cardOpacity.toStringAsFixed(2));
      await _storage.write(key: _kBg, value: state.background);
      await _storage.write(key: _kBgPath, value: state.customPath ?? '');
    } catch (_) {}
  }
}

/// Overridden in main() with the stored settings so the first frame already has the right look.
final glassInitialProvider = Provider<GlassSettings>((_) => const GlassSettings());
final glassProvider =
    StateNotifierProvider<GlassNotifier, GlassSettings>((ref) => GlassNotifier(ref.watch(glassInitialProvider)));

/// Height the glass themes keep for the top of the screen. The app runs immersive (no status bar), but a
/// camera cut-out still reports a tall top inset, which pushed the header down; this trims it.
const double kGlassTopInset = 8;

MediaQueryData trimTopInset(MediaQueryData mq, double max) => mq.copyWith(
      padding: mq.padding.copyWith(top: mq.padding.top > max ? max : mq.padding.top),
      viewPadding: mq.viewPadding.copyWith(top: mq.viewPadding.top > max ? max : mq.viewPadding.top),
    );

// ── Backdrop ────────────────────────────────────────────────────────────────

/// A built-in backdrop: a dark two-stop gradient with three soft colour blobs.
class GlassBackgroundPreset {
  final String id;
  final String name;
  final Color top;
  final Color bottom;
  final List<Color> blobs; // top-left, right, bottom-left
  const GlassBackgroundPreset(this.id, this.name, this.top, this.bottom, this.blobs);
}

const kGlassBackgrounds = <GlassBackgroundPreset>[
  GlassBackgroundPreset('aurora', 'Aurora', Color(0xFF0F172A), Color(0xFF14123A),
      [Color(0xFF2563EB), Color(0xFF7C3AED), Color(0xFFF59E0B)]),
  GlassBackgroundPreset('sunset', 'Sunset', Color(0xFF1A0F1F), Color(0xFF2A1118),
      [Color(0xFFE11D48), Color(0xFFF97316), Color(0xFF9333EA)]),
  GlassBackgroundPreset('forest', 'Forest', Color(0xFF0B1A14), Color(0xFF0E1F1F),
      [Color(0xFF10B981), Color(0xFF0D9488), Color(0xFFA3E635)]),
  GlassBackgroundPreset('ocean', 'Ocean', Color(0xFF07182A), Color(0xFF081F33),
      [Color(0xFF0EA5E9), Color(0xFF06B6D4), Color(0xFF3B82F6)]),
  GlassBackgroundPreset('rose', 'Rose', Color(0xFF1C1020), Color(0xFF220F26),
      [Color(0xFFEC4899), Color(0xFFA855F7), Color(0xFFFB7185)]),
  GlassBackgroundPreset('ember', 'Ember', Color(0xFF1A1208), Color(0xFF1F0F0A),
      [Color(0xFFF59E0B), Color(0xFFEF4444), Color(0xFFEAB308)]),
  GlassBackgroundPreset('graphite', 'Graphite', Color(0xFF0F1115), Color(0xFF15171C),
      [Color(0xFF64748B), Color(0xFF475569), Color(0xFF94A3B8)]),
];

/// Backdrop behind every screen in the glass themes, so there is something for the glass to blur.
/// [background] is a preset id, or 'custom' with the image at [customPath].
class GlassBackdrop extends StatelessWidget {
  final String background;
  final String? customPath;
  const GlassBackdrop({super.key, this.background = 'aurora', this.customPath});

  static Widget blob(Alignment a, Color c, double size, double alpha) => Align(
        alignment: a,
        child: IgnorePointer(
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [c.withOpacity(alpha), c.withOpacity(0)]),
            ),
          ),
        ),
      );

  /// The preset as a widget, also used for the small previews in Settings.
  static Widget preset(GlassBackgroundPreset p, {double scale = 1}) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [p.top, p.bottom]),
        ),
        child: Stack(fit: StackFit.expand, children: [
          blob(const Alignment(-1.2, -0.95), p.blobs[0], 520 * scale, 0.75),
          blob(const Alignment(1.3, 0.05), p.blobs[1], 480 * scale, 0.65),
          blob(const Alignment(-0.7, 1.15), p.blobs[2], 440 * scale, 0.45),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    if (background == 'custom' && customPath != null) {
      return Stack(fit: StackFit.expand, children: [
        Image.file(
          File(customPath!),
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => preset(kGlassBackgrounds.first),
        ),
        // Keeps text readable on bright photos.
        const ColoredBox(color: Color(0x59000000)),
      ]);
    }
    final p = kGlassBackgrounds.where((b) => b.id == background).firstOrNull ?? kGlassBackgrounds.first;
    return preset(p);
  }
}

// ── Glass surface ───────────────────────────────────────────────────────────

/// A pane of glass over the backdrop. Returns [child] untouched in the Classic theme, so callers
/// can wrap unconditionally. [tint] colours the glass (for a coloured note); [opacity] overrides
/// the card opacity from Settings.
class GlassPanel extends ConsumerWidget {
  final Widget child;
  final double radius;
  final double? opacity;
  final Color? tint;
  final bool header;
  final EdgeInsetsGeometry? padding;
  final Color? borderColor;

  const GlassPanel({
    super.key,
    required this.child,
    this.radius = 14,
    this.opacity,
    this.tint,
    this.header = false,
    this.padding,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(glassProvider);
    if (!s.glass) return child;
    final r = BorderRadius.circular(radius);
    final op = opacity ?? (header ? s.headerOpacity : s.cardOpacity);

    if (s.liquid) {
      final base = tint ?? Colors.white;
      final top = tint != null ? 0.38 : (0.24 - op * 0.17).clamp(0.07, 0.24);
      final bottom = tint != null ? 0.10 : 0.05;
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: r,
          boxShadow: const [BoxShadow(color: Color(0x47050A1E), blurRadius: 16, offset: Offset(0, 6))],
        ),
        child: ClipRRect(
          borderRadius: r,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              padding: padding,
              decoration: BoxDecoration(
                borderRadius: r,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [base.withOpacity(top.toDouble()), base.withOpacity(bottom)],
                ),
                border: Border.all(color: borderColor ?? Colors.white.withOpacity(0.28)),
              ),
              child: child,
            ),
          ),
        ),
      );
    }

    final base = tint ?? const Color(0xFF1E293B);
    return ClipRRect(
      borderRadius: r,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: r,
            color: base.withOpacity(tint != null ? (op * 0.8).clamp(0.12, 0.6) : op),
            border: Border.all(color: borderColor ?? Colors.white.withOpacity(0.14)),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// The round + button: a normal FAB in Classic, a pane of glass in the glass themes.
class GlassFab extends ConsumerWidget {
  final VoidCallback onPressed;
  final IconData icon;
  const GlassFab({super.key, required this.onPressed, this.icon = Icons.add});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(glassProvider);
    if (!s.glass) return FloatingActionButton(onPressed: onPressed, child: Icon(icon));
    return GlassPanel(
      radius: s.liquid ? 28 : 18,
      tint: s.liquid ? null : const Color(0xFF2563EB),
      opacity: 0.55,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(width: 56, height: 56, child: Icon(icon, color: Colors.white)),
        ),
      ),
    );
  }
}

/// Body of a Drawer: a normal solid drawer in Classic, a blurred glass sheet otherwise.
class GlassDrawerBody extends ConsumerWidget {
  final Widget child;
  const GlassDrawerBody({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(glassProvider);
    if (!s.glass) return child;
    return ClipRRect(
      borderRadius: const BorderRadius.horizontal(right: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withOpacity((s.headerOpacity + 0.1).clamp(0.3, 0.9)),
            border: Border(right: BorderSide(color: Colors.white.withOpacity(0.14))),
          ),
          child: child,
        ),
      ),
    );
  }
}

class GlassMenuItem<T> {
  final T value;
  final String label;
  final IconData? icon;
  const GlassMenuItem(this.value, this.label, {this.icon});
}

/// The "more" menu. Classic keeps the normal popup; the glass themes open a rounded pane of glass
/// with a light bezel, anchored under the button.
class GlassMenuButton<T> extends ConsumerWidget {
  final List<GlassMenuItem<T>> items;
  final ValueChanged<T> onSelected;
  const GlassMenuButton({super.key, required this.items, required this.onSelected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(glassProvider);
    if (!s.glass) {
      return PopupMenuButton<T>(
        onSelected: onSelected,
        itemBuilder: (_) => [for (final i in items) PopupMenuItem<T>(value: i.value, child: Text(i.label))],
      );
    }
    return Builder(
      builder: (ctx) => IconButton(
        icon: const Icon(Icons.more_vert),
        tooltip: 'More',
        onPressed: () => _open(ctx, s),
      ),
    );
  }

  Future<void> _open(BuildContext context, GlassSettings s) async {
    final box = context.findRenderObject() as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final right = overlay.size.width - (topLeft.dx + box.size.width);
    final picked = await showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close menu',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (ctx, _, __) => Stack(children: [
        Positioned(
          top: topLeft.dy + box.size.height - 6,
          right: right + 4,
          child: Material(
            type: MaterialType.transparency,
            child: GlassPanel(
              radius: 20,
              opacity: 0.72,
              borderColor: Colors.white.withOpacity(0.38),
              child: IntrinsicWidth(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 190),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    for (final i in items)
                      InkWell(
                        onTap: () => Navigator.of(ctx).pop(i.value),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                          child: Row(children: [
                            if (i.icon != null) ...[Icon(i.icon, size: 20), const SizedBox(width: 12)],
                            Text(i.label, style: const TextStyle(fontSize: 16)),
                          ]),
                        ),
                      ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ]),
      transitionBuilder: (ctx, anim, _, child) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween(begin: 0.92, end: 1.0).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
          alignment: Alignment.topRight,
          child: child,
        ),
      ),
    );
    if (picked != null) onSelected(picked);
  }
}

// ── Header ──────────────────────────────────────────────────────────────────

/// The screen header in the chosen theme. Classic is the normal AppBar, Frosted is a full-width blurred
/// bar, Liquid is a floating glass capsule. The caller passes the settings (it already watches them)
/// because the height depends on the theme.
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  final GlassSettings settings;
  final Widget? title;
  final Widget? leading;
  final List<Widget> actions;
  final bool automaticallyImplyLeading;
  final double titleSpacing;

  const GlassAppBar({
    super.key,
    required this.settings,
    this.title,
    this.leading,
    this.actions = const [],
    this.automaticallyImplyLeading = true,
    this.titleSpacing = NavigationToolbar.kMiddleSpacing,
  });

  /// Height of the capsule header including its margins.
  static const _liquidHeight = 52.0;

  @override
  Size get preferredSize => Size.fromHeight(settings.liquid ? _liquidHeight : kToolbarHeight);

  /// Space a scrollable body needs at its top when it runs behind a glass header.
  static double bodyTopInset(BuildContext context, GlassSettings s) =>
      s.glass ? MediaQuery.paddingOf(context).top + (s.liquid ? _liquidHeight : kToolbarHeight) : 0;

  Widget? _implicitLeading(BuildContext context) {
    if (leading != null || !automaticallyImplyLeading) return leading;
    final scaffold = Scaffold.maybeOf(context);
    if (scaffold != null && scaffold.hasDrawer) {
      return IconButton(icon: const Icon(Icons.menu), onPressed: scaffold.openDrawer);
    }
    if (ModalRoute.of(context)?.canPop ?? false) return const BackButton();
    return null;
  }

  @override
  Widget build(BuildContext context) {
    switch (settings.style) {
      case ThemeStyle.classic:
        return AppBar(
          title: title,
          leading: leading,
          actions: actions,
          automaticallyImplyLeading: automaticallyImplyLeading,
          titleSpacing: titleSpacing,
        );
      case ThemeStyle.frosted:
        return AppBar(
          title: title,
          leading: leading,
          actions: actions,
          automaticallyImplyLeading: automaticallyImplyLeading,
          titleSpacing: titleSpacing,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          flexibleSpace: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  // Slate (lighter than the page) so the bar reads as a pane even over the dark top of the
                  // backdrop; 0% leaves a faint pane, 100% is solid. A soft sheen and a light bottom edge
                  // make the frost visible.
                  color: const Color(0xFF1E293B).withOpacity(0.12 + 0.88 * settings.headerOpacity),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.white.withOpacity(0.14), Colors.white.withOpacity(0.03)],
                  ),
                  border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.28))),
                ),
                // The AppBar gives its background loose constraints; without a child that fills them this
                // pane collapses to zero height and draws nothing.
                child: const SizedBox.expand(),
              ),
            ),
          ),
        );
      case ThemeStyle.liquid:
        final lead = _implicitLeading(context);
        final titleStyle = Theme.of(context).appBarTheme.titleTextStyle ??
            const TextStyle(fontSize: 18, fontWeight: FontWeight.w600);
        return SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
            child: GlassPanel(
              radius: 28,
              header: true,
              child: Material(
                type: MaterialType.transparency,
                child: SizedBox(
                  height: 48,
                  child: Row(children: [
                    if (lead != null) lead else SizedBox(width: titleSpacing),
                    Expanded(
                      child: DefaultTextStyle(
                        style: titleStyle,
                        overflow: TextOverflow.ellipsis,
                        child: title ?? const SizedBox.shrink(),
                      ),
                    ),
                    ...actions,
                    const SizedBox(width: 4),
                  ]),
                ),
              ),
            ),
          ),
        );
    }
  }
}

// ── Search in the header ────────────────────────────────────────────────────

/// Header content: the title, a search icon and the [actions] at the right. Tapping the search icon slides
/// the title away while the field grows from the icon, leftwards to the start of the header and rightwards
/// over the action icons, so the icon ends up at the start of a full-width field.
class HeaderSearch extends StatefulWidget {
  final Widget title;
  final List<Widget> actions;
  final bool open;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onOpen;
  final VoidCallback onClose;
  final ValueChanged<String> onChanged;
  final String hint;

  const HeaderSearch({
    super.key,
    required this.title,
    this.actions = const [],
    required this.open,
    required this.controller,
    required this.focusNode,
    required this.onOpen,
    required this.onClose,
    required this.onChanged,
    this.hint = 'Search notes',
  });

  @override
  State<HeaderSearch> createState() => _HeaderSearchState();
}

class _HeaderSearchState extends State<HeaderSearch> {
  static const _iconSize = 44.0;
  final _trailKey = GlobalKey();
  double _trailW = 0;
  // Off until the actions have been measured, so the icon is placed beside them at once instead of
  // gliding in from the right edge when the screen first appears.
  bool _animate = false;

  @override
  void didUpdateWidget(HeaderSearch old) {
    super.didUpdateWidget(old);
    if (!old.open && widget.open) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.open) widget.focusNode.requestFocus();
      });
    }
  }

  void _close() {
    widget.controller.clear();
    widget.onChanged('');
    widget.focusNode.unfocus();
    widget.onClose();
  }

  /// The closed icon sits just left of the actions, so the field needs to know how wide they are.
  void _measureActions() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = _trailKey.currentContext?.findRenderObject() as RenderBox?;
      final w = (box != null && box.hasSize) ? box.size.width : 0.0;
      if ((w - _trailW).abs() > 0.5) setState(() => _trailW = w);
      if (!_animate) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _animate = true);
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final open = widget.open;
    // Opaque, so the icons under the open field do not show through it.
    final fieldFill = Theme.of(context).brightness == Brightness.dark ? const Color(0xFF273650) : const Color(0xFFE2E8F0);
    _measureActions();
    return LayoutBuilder(builder: (context, c) {
      final full = c.maxWidth.isFinite ? c.maxWidth : 240.0;
      // Fill the slot: an AppBar title slot gives a loose width, and a Stack of one small child would
      // otherwise shrink to the icon and put the title underneath it.
      return SizedBox(
        width: full,
        height: 48,
        child: Stack(clipBehavior: Clip.none, children: [
          Row(children: [
            Expanded(
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 380),
                curve: Curves.easeOutCubic,
                offset: open ? const Offset(-0.12, 0) : Offset.zero,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 220),
                  opacity: open ? 0 : 1,
                  child: Align(alignment: Alignment.centerLeft, child: widget.title),
                ),
              ),
            ),
            const SizedBox(width: _iconSize),
            Row(key: _trailKey, mainAxisSize: MainAxisSize.min, children: widget.actions),
          ]),
          AnimatedPositioned(
            duration: _animate ? const Duration(milliseconds: 420) : Duration.zero,
            curve: const Cubic(0.2, 0.85, 0.2, 1),
            top: 4,
            height: 40,
            right: open ? 4 : _trailW,
            width: open ? (full - 8).clamp(_iconSize, double.infinity) : _iconSize,
            child: Container(
              key: const ValueKey('header-search-field'),
              clipBehavior: Clip.hardEdge,
              decoration: BoxDecoration(
                color: open ? fieldFill : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: LayoutBuilder(builder: (context, box) {
                final w = box.maxWidth;
                return Stack(children: [
                  Positioned(
                    left: 0,
                    top: 0,
                    width: _iconSize,
                    height: 40,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      tooltip: 'Search',
                      icon: const Icon(Icons.search),
                      onPressed: open ? () => widget.focusNode.requestFocus() : widget.onOpen,
                    ),
                  ),
                  if (open) ...[
                    Positioned(
                      left: _iconSize,
                      top: 0,
                      bottom: 0,
                      width: (w - _iconSize * 2).clamp(0.0, double.infinity),
                      child: Center(child: TextField(
                        controller: widget.controller,
                        focusNode: widget.focusNode,
                        textInputAction: TextInputAction.search,
                        textAlignVertical: TextAlignVertical.center,
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          hintText: widget.hint,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onChanged: widget.onChanged,
                      )),
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      width: _iconSize,
                      height: 40,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        tooltip: 'Close search',
                        icon: const Icon(Icons.close),
                        onPressed: _close,
                      ),
                    ),
                  ],
                ]);
              }),
            ),
          ),
        ]),
      );
    });
  }
}
