import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
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
final inAppAlarmBannerProvider = StateProvider<AlarmInstance?>((ref) => null);

/// True while the user is actively viewing the MOB screen.
final isOnMobScreenProvider = StateProvider<bool>((ref) => false);

// ---------------------------------------------------------------------------
// Root app widget
// ---------------------------------------------------------------------------

class YokulApp extends ConsumerStatefulWidget {
  const YokulApp({super.key});

  @override
  ConsumerState<YokulApp> createState() => _YokulAppState();
}

class _YokulAppState extends ConsumerState<YokulApp> {
  @override
  void initState() {
    super.initState();

    // ── MOB start: navigate EVERY device to /mob ────────────────────────────
    ref.listenManual(
      mobProvider.select((s) => s.activeMob?.id),
      (prev, mobId) {
        if (mobId == null || mobId == prev) return;
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ref.read(appRouterProvider).push('/mob');
        });
        HapticFeedback.heavyImpact();
        Future.delayed(const Duration(milliseconds: 300), HapticFeedback.heavyImpact);
        Future.delayed(const Duration(milliseconds: 600), HapticFeedback.heavyImpact);
      },
      fireImmediately: false,
    );

    // ── MOB end: pop /mob on every device when alert is resolved ────────────
    ref.listenManual(
      mobProvider.select((s) => s.isMobActive),
      (wasActive, isActive) {
        if (wasActive != true || isActive != false) return;
        // 2-second pause so the crew sees "resolved" before leaving the screen.
        Future.delayed(const Duration(seconds: 2), () {
          if (!mounted) return;
          final router = ref.read(appRouterProvider);
          if (router.canPop()) router.pop();
        });
      },
      fireImmediately: false,
    );

    // ── Join sync: take all devices back to home while a peer is syncing ────
    ref.listenManual(
      networkJoinInProgressProvider,
      (prev, next) {
        if (next != true || prev == true) return;
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) ref.read(appRouterProvider).go('/');
        });
      },
      fireImmediately: false,
    );

    // ── In-app alarm banner ──────────────────────────────────────────────────
    ref.listenManual(
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
      fireImmediately: false,
    );
  }

  @override
  Widget build(BuildContext context) {
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
      builder: (context, child) {
        return _OverlayLayer(child: child ?? const SizedBox.shrink());
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Global overlay layer: alarm banner + join sync dim
// ---------------------------------------------------------------------------

class _OverlayLayer extends ConsumerWidget {
  final Widget child;
  const _OverlayLayer({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alarm   = ref.watch(inAppAlarmBannerProvider);
    final joining = ref.watch(networkJoinInProgressProvider);

    return Stack(
      children: [
        child,

        // ── Join-sync dim overlay ────────────────────────────────────────────
        if (joining)
          Positioned.fill(
            child: AbsorbPointer(
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
                        width: 16, height: 16,
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

        // ── Alarm banner (top) ───────────────────────────────────────────────
        if (alarm != null)
          Positioned(
            top: 0, left: 0, right: 0,
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


// ---------------------------------------------------------------------------
// Alarm banner (slides in from top)
// ---------------------------------------------------------------------------

Color _levelColor(AlarmLevel level) {
  switch (level) {
    case AlarmLevel.critical: return AppColors.danger;
    case AlarmLevel.warning:  return AppColors.warning;
    case AlarmLevel.info:     return AppColors.cyan;
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
