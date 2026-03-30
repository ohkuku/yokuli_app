import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app.dart';
import 'core/theme/app_theme.dart';
import 'features/startup/startup_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Hive for logbook & maintenance (no code gen — stores raw Maps)
  await Hive.initFlutter();
  await Hive.openBox('logbook');
  await Hive.openBox('maintenance');

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF07111F),
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(
    const ProviderScope(
      observers: [_AppProviderObserver()],
      child: _AppGate(),
    ),
  );
}

// ---------------------------------------------------------------------------
// App gate — shows startup screen, then hands off to the main app
// ---------------------------------------------------------------------------

class _AppGate extends ConsumerStatefulWidget {
  const _AppGate();

  @override
  ConsumerState<_AppGate> createState() => _AppGateState();
}

class _AppGateState extends ConsumerState<_AppGate> {
  bool _ready = false;

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      // Wrap startup screen in a MaterialApp so it has theme + Directionality.
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: StartupScreen(
          onComplete: () {
            if (mounted) setState(() => _ready = true);
          },
        ),
      );
    }
    return const YokulApp();
  }
}

// ---------------------------------------------------------------------------
// Provider observer (debug only)
// ---------------------------------------------------------------------------

class _AppProviderObserver extends ProviderObserver {
  const _AppProviderObserver();

  @override
  void didUpdateProvider(
    ProviderBase<Object?> provider,
    Object? previousValue,
    Object? newValue,
    ProviderContainer container,
  ) {
    assert(() => true);
  }
}
