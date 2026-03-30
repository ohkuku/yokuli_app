import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app.dart';
import 'core/providers/settings_provider.dart';
import 'core/providers/locale_provider.dart';
import 'core/services/signalk/signalk_client.dart';
import 'core/services/lan_sync/lan_sync_service.dart';

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
    // Delay to let settings load from SharedPreferences first
    Future.microtask(() async {
      await ref.read(localeProvider.notifier).init();
      await _autoConnect();
    });
  }

  Future<void> _autoConnect() async {
    final settings = ref.read(settingsProvider);

    if (settings.autoConnectSignalK && settings.signalKUrl.isNotEmpty) {
      await ref.read(signalKClientProvider).connect(settings.signalKUrl);
    }

    if (settings.autoConnectLan) {
      await ref.read(lanSyncServiceProvider).start();
    }
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
