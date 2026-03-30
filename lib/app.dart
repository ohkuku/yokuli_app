import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'core/providers/locale_provider.dart';
import 'router/app_router.dart';

class YokulApp extends ConsumerWidget {
  const YokulApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final locale = ref.watch(flutterLocaleProvider);

    return MaterialApp.router(
      title: 'Yokuli',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('zh')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
    );
  }
}
