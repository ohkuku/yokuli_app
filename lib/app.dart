import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/models/alarm_instance.dart';
import 'core/models/alarm_rule.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'core/providers/locale_provider.dart';
import 'core/providers/alarm_instance_provider.dart';
import 'features/mob/providers/mob_provider.dart';
import 'core/services/lan_sync/lan_sync_service.dart';
import 'router/app_router.dart';

/// Provider that holds the alarm instance to display as an in-app banner.
/// The alarm evaluator sets this when a new alarm triggers.
final inAppAlarmBannerProvider = StateProvider<AlarmInstance?>((ref) => null);

class YokulApp extends ConsumerWidget {
  const YokulApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final locale = ref.watch(flutterLocaleProvider);

    // Navigate every device to the MOB screen when a MOB is triggered.
    ref.listen(
      mobProvider.select((s) => s.activeMob?.id),
      (prev, mobId) {
        if (mobId != null && mobId != prev) {
          router.push('/mob');
        }
      },
    );

    // During join sync, return to the main waiting page (home) for all devices.
    ref.listen(
      networkJoinInProgressProvider,
      (prev, next) {
        if (next == true && prev != true) {
          router.go('/');
        }
      },
    );

    // Show in-app banner when a new active alarm instance appears.
    ref.listen(
      activeAlarmInstancesProvider,
      (prev, next) {
        final prevIds = prev?.map((a) => a.id).toSet() ?? {};
        final newAlarm = next.where((a) =>
          a.status == AlarmInstanceStatus.active &&
          !prevIds.contains(a.id)
        ).firstOrNull;
        if (newAlarm != null) {
          ref.read(inAppAlarmBannerProvider.notifier).state = newAlarm;
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
    final joining = ref.watch(networkJoinInProgressProvider);

    return Stack(
      children: [
        child,
        if (joining)
          Positioned.fill(
            child: AbsorbPointer(
              absorbing: true,
              child: Container(
                color: Colors.black.withOpacity(0.35),
                alignment: Alignment.center,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.cardBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 10),
                      Text(
                        '新设备加入中，请等待其完成配置…',
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (alarm != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: _AlarmBanner(
                alarm: alarm,
                onDismiss: () =>
                    ref.read(inAppAlarmBannerProvider.notifier).state = null,
              ),
            ),
          ),
      ],
    );
  }
}

class _AlarmBanner extends StatefulWidget {
  final AlarmInstance alarm;
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
                        widget.alarm.ruleName,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700),
                      ),
                      Text(
                        widget.alarm.message,
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
