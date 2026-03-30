import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app.dart';
import 'core/providers/settings_provider.dart';
import 'core/providers/locale_provider.dart';
import 'core/services/signalk/signalk_auth.dart';
import 'core/providers/voyage_provider.dart';
import 'core/providers/task_provider.dart';
import 'core/providers/issue_provider.dart';
import 'core/providers/log_provider.dart';
import 'core/providers/alarm_provider.dart';
import 'core/providers/alarm_rule_provider.dart';
import 'core/services/alarm_dispatcher.dart';
import 'core/services/signalk/signalk_client.dart';
import 'core/services/lan_sync/lan_sync_service.dart';
import 'core/providers/kanban_provider.dart';
import 'features/safety/providers/safety_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Hive for logbook & maintenance (no code gen — stores raw Maps)
  await Hive.initFlutter();
  await Hive.openBox('logbook');
  await Hive.openBox('maintenance');

  // Preferred orientations: allow landscape on tablets / portrait+landscape on phones
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Dark status / nav bar
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF07111F),
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(
    ProviderScope(
      observers: const [_AppProviderObserver()],
      child: const _AppInit(),
    ),
  );
}

/// Handles auto-connect logic after settings are loaded
class _AppInit extends ConsumerStatefulWidget {
  const _AppInit();

  @override
  ConsumerState<_AppInit> createState() => _AppInitState();
}

class _AppInitState extends ConsumerState<_AppInit> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      // Load settings first — build() fires _loadFromPrefs() async so we must
      // await it explicitly before reading any persisted values.
      await ref.read(settingsProvider.notifier).load();
      await ref.read(safetyProvider.notifier).load();
      await ref.read(localeProvider.notifier).init();
      await ref.read(alarmRuleProvider.notifier).load();
      await ref.read(notifyChannelProvider.notifier).load();
      await _loadPersistentData();
      // Initialize alarm dispatcher (creates it, which starts listening).
      ref.read(alarmDispatcherProvider);
      await _autoConnect();
    });
  }

  Future<void> _loadPersistentData() async {
    await Future.wait([
      ref.read(voyageProvider.notifier).load(),
      ref.read(taskProvider.notifier).load(),
      ref.read(issueProvider.notifier).load(),
      ref.read(logProvider.notifier).load(),
      ref.read(alarmProvider.notifier).load(),
    ]);
  }

  Future<void> _autoConnect() async {
    final settings = ref.read(settingsProvider);

    if (settings.autoConnectSignalK && settings.effectiveSignalKUrl.isNotEmpty) {
      String? token;
      if (settings.hasCredentials) {
        try {
          token = await SignalKAuth.login(
            settings.effectiveSignalKUrl,
            settings.signalKUsername,
            settings.signalKPassword,
          );
        } catch (_) {
          // Proceed without token if login fails
        }
      }
      await ref.read(signalKClientProvider).connect(
        settings.effectiveSignalKUrl,
        token: token,
      );
    }

    if (settings.autoConnectLan) {
      await ref.read(lanSyncServiceProvider).start();
    }

    // Wire LAN sync → safety provider for MOB events
    final lanSync = ref.read(lanSyncServiceProvider);
    lanSync.onMobAlert = (alert) {
      ref.read(safetyProvider.notifier).receiveMob(alert);
    };
    lanSync.onMobCancelReceived = () {
      ref.read(safetyProvider.notifier).receiveMobCancel();
    };
    lanSync.onKanbanSync = (data) =>
        ref.read(kanbanProvider.notifier).applySync(data);
  }

  @override
  Widget build(BuildContext context) => const YokulApp();
}

class _AppProviderObserver extends ProviderObserver {
  const _AppProviderObserver();

  @override
  void didUpdateProvider(
    ProviderBase<Object?> provider,
    Object? previousValue,
    Object? newValue,
    ProviderContainer container,
  ) {
    // For debugging — disable in production
    assert(() {
      // Only log errors
      return true;
    }());
  }
}
