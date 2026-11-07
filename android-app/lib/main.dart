import 'package:flutter/material.dart';
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
      await BackgroundSync.run();
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
  final container = ProviderContainer(overrides: [glassInitialProvider.overrideWithValue(initialGlass)]);
  runApp(UncontrolledProviderScope(container: container, child: const PriNotesApp()));

  // Tapping a task in the home-screen widget opens the To-Do screen.
  HomeWidget.widgetClicked.listen((uri) {
    if (uri?.scheme == 'todo') container.read(appRouterProvider).go('/todo');
  });
  final launchedFrom = await HomeWidget.initiallyLaunchedFromHomeWidget();
  if (launchedFrom?.scheme == 'todo') {
    WidgetsBinding.instance.addPostFrameCallback((_) => container.read(appRouterProvider).go('/todo'));
  }
}

class PriNotesApp extends ConsumerWidget {
  const PriNotesApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);
    final glass = ref.watch(glassProvider);

    return MaterialApp.router(
      title: 'PriNotes',
      debugShowCheckedModeBanner: false,
      theme: glass.glass ? AppTheme.glass(glass) : AppTheme.light(),
      darkTheme: glass.glass ? AppTheme.glass(glass) : AppTheme.dark(),
      themeMode: glass.glass ? ThemeMode.dark : themeMode,
      routerConfig: router,
      scrollBehavior: glass.glass ? const _NoEdgeEffectScrollBehavior() : null,
      // Glass themes paint one gradient behind every screen; the screens themselves are transparent.
      builder: glass.glass
          ? (context, child) => MediaQuery(
                data: trimTopInset(MediaQuery.of(context), kGlassTopInset),
                child: Stack(fit: StackFit.expand, children: [
                  GlassBackdrop(background: glass.background, customPath: glass.customPath),
                  if (child != null) child,
                ]),
              )
          : null,
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
