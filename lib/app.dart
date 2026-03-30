import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/models/alarm.dart';
import 'core/services/alarm_dispatcher.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'core/providers/locale_provider.dart';
import 'features/safety/providers/safety_provider.dart';
import 'router/app_router.dart';

class YokulApp extends ConsumerWidget {
  const YokulApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final locale = ref.watch(flutterLocaleProvider);

    // Navigate every device to the safety screen when a MOB is triggered
    // (whether local or received from a LAN peer).
    ref.listen(
      safetyProvider.select((s) => s.isMobActive),
      (prev, isActive) {
        if (isActive == true && prev != true) {
          router.go('/safety');
        }
      },
    );

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
      builder: (context, child) {
        return _AlarmBannerOverlay(child: child ?? const SizedBox.shrink());
      },
    );
  }
}

// ---------------------------------------------------------------------------
// In-app alarm banner overlay
// ---------------------------------------------------------------------------

String _typeLabel(AlarmType type) {
  switch (type) {
    case AlarmType.battery:
      return '电池低压';
    case AlarmType.depth:
      return '水深告警';
    case AlarmType.speed:
      return '航速告警';
    case AlarmType.mob:
      return 'MOB落水告警';
    case AlarmType.ais:
      return 'AIS碰撞风险';
    case AlarmType.solar:
      return '太阳能告警';
    case AlarmType.connection:
      return '连接告警';
  }
}

Color _levelColor(AlarmLevel level) {
  switch (level) {
    case AlarmLevel.critical:
      return AppColors.danger;
    case AlarmLevel.warning:
      return AppColors.warning;
    case AlarmLevel.info:
      return AppColors.cyan;
  }
}

class _AlarmBannerOverlay extends ConsumerWidget {
  final Widget child;
  const _AlarmBannerOverlay({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alarm = ref.watch(inAppAlarmBannerProvider);

    return Stack(
      children: [
        child,
        // Banner sits above everything but does not block touch on the rest
        // of the app (IgnorePointer only on the transparent area).
        if (alarm != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: _AlarmBanner(
                alarm: alarm,
                onDismiss: () => ref
                    .read(inAppAlarmBannerProvider.notifier)
                    .state = null,
              ),
            ),
          ),
      ],
    );
  }
}

class _AlarmBanner extends StatefulWidget {
  final Alarm alarm;
  final VoidCallback onDismiss;
  const _AlarmBanner({required this.alarm, required this.onDismiss});

  @override
  State<_AlarmBanner> createState() => _AlarmBannerState();
}

class _AlarmBannerState extends State<_AlarmBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 320));
    _slide = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _levelColor(widget.alarm.level);

    return SlideTransition(
      position: _slide,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Material(
          color: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: color.withOpacity(0.92),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _typeLabel(widget.alarm.type),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700),
                      ),
                      if (widget.alarm.message != null)
                        Text(
                          widget.alarm.message!,
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.85),
                              fontSize: 12),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: widget.onDismiss,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    child: const Icon(Icons.close_rounded,
                        color: Colors.white, size: 18),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
