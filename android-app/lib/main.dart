import 'package:flutter/material.dart';
import 'features/todo/todo_navigation.dart';
import 'features/update/update_checker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'features/todo/providers/todo_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:workmanager/workmanager.dart';

import 'core/constants/app_constants.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/glass.dart';
import 'features/sync/background_sync.dart';
import 'features/todo/reminders/todo_reminders.dart';
import 'features/todo/widget/todo_widget_bridge.dart';

final FlutterLocalNotificationsPlugin notificationsPlugin =
    FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == AppConstants.syncTaskName) {
      return BackgroundSync.run();
    }
    return true;
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait + landscape
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Timezones
  tz.initializeTimeZones();

  // Local notifications
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  await notificationsPlugin.initialize(
    const InitializationSettings(android: androidInit),
  );

  // To-Do reminders (alarms) and home-screen widget callback
  await TodoReminders.init();
  await TodoWidgetBridge.register();

  // Background sync
  await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  await Workmanager().registerPeriodicTask(
    AppConstants.syncTaskName,
    AppConstants.syncTaskName,
    frequency: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );

  // Stored theme (Classic / Frosted / Liquid) is read first so the very first frame already has it.
  final initialGlass = await loadGlassSettings();
  final initialTodoView = await loadTodoView();
  final container = ProviderContainer(overrides: [
    glassInitialProvider.overrideWithValue(initialGlass),
    todoViewInitialProvider.overrideWithValue(initialTodoView),
  ]);
  runApp(UncontrolledProviderScope(container: container, child: const PriNotesApp()));

  // Tapping a task in the home-screen widget, or a reminder notification, opens the To-Do page on that
  // task's category.
  void openTask(int? id) => openTodoFromTap(container, id);
  TodoReminders.onOpenTask = openTask;
  HomeWidget.widgetClicked.listen((uri) {
    if (uri?.scheme == 'todo') openTask(taskIdFromWidgetUri(uri));
  });
  final launchedFrom = await HomeWidget.initiallyLaunchedFromHomeWidget();
  if (launchedFrom?.scheme == 'todo') {
    WidgetsBinding.instance.addPostFrameCallback((_) => openTask(taskIdFromWidgetUri(launchedFrom)));
  } else {
    final fromNotification = await TodoReminders.launchTaskId();
    if (fromNotification != null) WidgetsBinding.instance.addPostFrameCallback((_) => openTask(fromNotification));
  }
}

class PriNotesApp extends ConsumerStatefulWidget {
  const PriNotesApp({super.key});

  @override
  ConsumerState<PriNotesApp> createState() => _PriNotesAppState();
}

class _PriNotesAppState extends ConsumerState<PriNotesApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureStatusBar();
      _checkForUpdate();
    });
  }

  /// Once per app start: is there a newer GitHub release?
  Future<void> _checkForUpdate() async {
    final version = (await PackageInfo.fromPlatform()).version;
    if (mounted) await checkForUpdateAtStart(ProviderScope.containerOf(context), version);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // The status bar can appear or vanish (rotation, per-app setting, resume): measure again.
  @override
  void didChangeMetrics() => _measureStatusBar();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _measureStatusBar();
  }

  Future<void> _measureStatusBar() async {
    final h = await readStatusBarHeight();
    if (!mounted || h == null) return;
    if (ref.read(statusBarHeightProvider) != h) ref.read(statusBarHeightProvider.notifier).state = h;
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);
    final glass = ref.watch(glassProvider);
    ref.listen(todoViewProvider, (_, v) => saveTodoView(v));

    return MaterialApp.router(
      title: 'PriNotes',
      debugShowCheckedModeBanner: false,
      theme: glass.glass ? AppTheme.glass(glass) : AppTheme.light(),
      darkTheme: glass.glass ? AppTheme.glass(glass) : AppTheme.dark(),
      themeMode: glass.glass ? ThemeMode.dark : themeMode,
      routerConfig: router,
      scrollBehavior: glass.glass ? const _NoEdgeEffectScrollBehavior() : null,
      builder: appShellBuilder(glass, statusBarDp: ref.watch(statusBarHeightProvider)),
    );
  }
}


/// The glass themes show a gradient behind transparent screens; the default edge glow / stretch at the top
/// and bottom of a list would flash a grey wash over it, so it is switched off there.
class _NoEdgeEffectScrollBehavior extends MaterialScrollBehavior {
  const _NoEdgeEffectScrollBehavior();

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) => child;
}
