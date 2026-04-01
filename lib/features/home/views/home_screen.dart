import 'dart:async' show Timer;
import 'dart:ui';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/providers/connection_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/vessel_provider.dart';
import '../../../core/providers/locale_provider.dart';
import '../../../core/providers/alarm_instance_provider.dart';
import '../../../core/providers/kanban_provider.dart';
import '../../../features/mob/providers/mob_provider.dart';
import '../../../core/services/update/update_dialog.dart';
import '../../../core/providers/weather_provider.dart';
import '../../../core/models/weather_state.dart';
import '../../../core/widgets/glass_card.dart';
import '../widgets/app_tile.dart';
import '../widgets/vessel_status_bar.dart';
import '../widgets/weather_background.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showUpdateDialogIfNeeded(context);
      // Auto-navigate to MOB screen when a remote MOB arrives
      ref.listenManual(
        mobProvider.select((s) => s.activeMob),
        (prev, next) {
          if (next != null && prev == null && mounted) {
            context.push('/mob');
          }
        },
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final conn    = ref.watch(connectionProvider);
    final vessel  = ref.watch(vesselProvider);
    final s       = ref.watch(stringsProvider);

    final alarmCount  = ref.watch(alarmInstanceCountProvider);
    final kanbanCount = ref.watch(kanbanProvider).cards.length;
    final weather     = ref.watch(weatherProvider);

    var tiles = _buildTiles(vessel, conn, s, alarmCount, kanbanCount, weather);

    // Apply saved tile order
    if (settings.tileOrder.isNotEmpty) {
      tiles = _sortTiles(tiles, settings.tileOrder);
    }

    final width  = MediaQuery.of(context).size.width;
    final crossCount = width > 900 ? 4 : (width > 600 ? 3 : 2);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // ── Weather sky background (iOS Weather-style) ────────────
          const Positioned.fill(child: WeatherBackground()),

          // ── Content ───────────────────────────────────────────────
          SafeArea(
            child: Column(
              children: [
                _Header(
                  vesselName: settings.vesselName,
                  conn: conn,
                  onArrange: () => _showArrangeSheet(context, tiles, settings),
                ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossCount,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 1.05,
                    ),
                    itemCount: tiles.length,
                    itemBuilder: (context, i) => AppTile(
                      key: ValueKey(tiles[i].id),
                      data: tiles[i],
                      onTap: () => context.push(tiles[i].route),
                    ),
                  ),
                ),
                const VesselStatusBar(),
              ],
            ),
          ),

          // ── Draggable MOB FAB ──────────────────────────────────────
          const _DraggableMobFab(),
        ],
      ),
    );
  }

  List<AppTileData> _buildTiles(
    vessel,
    AppConnectionState conn,
    s,
    int alarmCount,
    int kanbanCount,
    WeatherState weather,
  ) {
    final sogStr = vessel.speedOverGround != null
        ? '${vessel.speedOverGround!.toStringAsFixed(1)} kn'
        : null;

    final signalKBadge = conn.isSignalKConnected ? s.connected : s.disconnected;

    final weatherBadge = weather.temperature != null
        ? '${weather.temperature!.round()}° ${weather.description ?? ''}'.trim()
        : weather.isLoading
            ? '获取中…'
            : null;

    return [
      AppTileData(
        id: 'signalk',
        label: s.signalKHub,
        icon: Icons.hub_rounded,
        accentColor: AppColors.modSignalK,
        route: '/signalk',
        badge: signalKBadge,
      ),
      AppTileData(
        id: 'dashboard',
        label: s.dashboard,
        icon: Icons.dashboard_rounded,
        accentColor: AppColors.modDashboard,
        route: '/dashboard',
        badge: sogStr,
      ),
      AppTileData(
        id: 'power',
        label: s.power,
        icon: Icons.bolt_rounded,
        accentColor: AppColors.modPower,
        route: '/power',
        badge: vessel.batteries.isNotEmpty
            ? '${vessel.batteries.values.first.voltage?.toStringAsFixed(1) ?? '—'} V'
            : null,
      ),
      AppTileData(
        id: 'safety',
        label: '告警中心',
        icon: Icons.emergency_rounded,
        accentColor: AppColors.modSafety,
        route: '/alarm-center',
        notificationCount: alarmCount,
      ),
      AppTileData(
        id: 'kanban',
        label: '船务看板',
        icon: Icons.view_kanban_rounded,
        accentColor: AppColors.modMaintenance,
        route: '/kanban',
        badge: kanbanCount > 0 ? '$kanbanCount' : null,
      ),
      AppTileData(
        id: 'ais',
        label: 'AIS',
        icon: Icons.radar_rounded,
        accentColor: AppColors.teal,
        route: '/ais',
      ),
      AppTileData(
        id: 'voyage',
        label: s.voyage,
        icon: Icons.anchor_rounded,
        accentColor: AppColors.cyan,
        route: '/voyage',
      ),
      AppTileData(
        id: 'log',
        label: s.logTitle,
        icon: Icons.receipt_long_rounded,
        accentColor: const Color(0xFF5E5CE6),
        route: '/log',
      ),
      AppTileData(
        id: 'weather',
        label: '天气',
        icon: Icons.wb_sunny_rounded,
        accentColor: AppColors.modWeather,
        route: '/weather',
        badge: weatherBadge,
      ),
      AppTileData(
        id: 'settings',
        label: s.settings,
        icon: Icons.settings_rounded,
        accentColor: AppColors.textSecondary,
        route: '/settings',
      ),
    ];
  }

  List<AppTileData> _sortTiles(List<AppTileData> tiles, List<String> order) {
    final indexed = {for (final t in tiles) t.id: t};
    final sorted = <AppTileData>[];
    for (final id in order) {
      if (indexed.containsKey(id)) sorted.add(indexed[id]!);
    }
    // Append any tiles not in the saved order (newly added tiles)
    for (final t in tiles) {
      if (!order.contains(t.id)) sorted.add(t);
    }
    return sorted;
  }

  void _showArrangeSheet(
      BuildContext context, List<AppTileData> tiles, AppSettings settings) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ArrangeSheet(tiles: tiles),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _Header extends ConsumerStatefulWidget {
  final String vesselName;
  final AppConnectionState conn;
  final VoidCallback? onArrange;

  const _Header({
    required this.vesselName,
    required this.conn,
    this.onArrange,
  });

  @override
  ConsumerState<_Header> createState() => _HeaderState();
}

class _HeaderState extends ConsumerState<_Header> {
  late Timer _clockTimer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final weather = ref.watch(weatherProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: GlassCard(
        borderRadius: BorderRadius.circular(20),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Row(
          children: [
            // Vessel name + clock
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Vessel name + optional temperature chip
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          widget.vesselName.toUpperCase(),
                          style: const TextStyle(
                            color: AppColors.cyan,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2.5,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (weather.temperature != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.modWeather.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(7),
                            border: Border.all(
                                color: AppColors.modWeather.withOpacity(0.28)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                iconForCode(weather.weatherCode ?? 0),
                                size: 11,
                                color: AppColors.modWeather,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                '${weather.temperature!.round()}°',
                                style: const TextStyle(
                                  color: AppColors.modWeather,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    DateFormat('EEE d MMM  HH:mm:ss').format(_now),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.55),
                      fontSize: 12,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            // Connection badges
            _ConnBadge(
              icon: Icons.hub_rounded,
              active: widget.conn.isSignalKConnected,
              color: AppColors.cyan,
              label: 'SK',
            ),
            const SizedBox(width: 8),
            _ConnBadge(
              icon: Icons.wifi_rounded,
              active: widget.conn.isLanSyncActive,
              color: AppColors.teal,
              label: widget.conn.isLanSyncActive && widget.conn.peerCount > 0
                  ? 'LAN ×${widget.conn.peerCount}'
                  : 'LAN',
            ),
            const SizedBox(width: 8),
            // Arrange tiles button
            GestureDetector(
              onTap: widget.onArrange,
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withOpacity(0.10)),
                ),
                child: Icon(Icons.grid_view_rounded,
                    size: 14, color: Colors.white.withOpacity(0.4)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _ConnBadge extends StatelessWidget {
  final IconData icon;
  final bool active;
  final Color color;
  final String label;

  const _ConnBadge({
    required this.icon,
    required this.active,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: active ? color.withOpacity(0.16) : Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: active ? color.withOpacity(0.35) : Colors.white.withOpacity(0.10),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 14,
              color: active ? color : Colors.white.withOpacity(0.25)),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: active ? color : Colors.white.withOpacity(0.25),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// Arrange tiles bottom sheet

class _ArrangeSheet extends ConsumerStatefulWidget {
  final List<AppTileData> tiles;
  const _ArrangeSheet({required this.tiles});

  @override
  ConsumerState<_ArrangeSheet> createState() => _ArrangeSheetState();
}

class _ArrangeSheetState extends ConsumerState<_ArrangeSheet> {
  late List<AppTileData> _tiles;

  @override
  void initState() {
    super.initState();
    _tiles = List.from(widget.tiles);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: AppColors.inactive,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Arrange Tiles',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _save,
                    child: Text(
                      'Done',
                      style: const TextStyle(
                        color: AppColors.cyan,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: AppColors.border, indent: 20, endIndent: 20),
            Expanded(
              child: ReorderableListView.builder(
                scrollController: scrollController,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: _tiles.length,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (newIndex > oldIndex) newIndex--;
                    final item = _tiles.removeAt(oldIndex);
                    _tiles.insert(newIndex, item);
                  });
                },
                itemBuilder: (context, index) {
                  final tile = _tiles[index];
                  final accent = tile.isStub
                      ? Colors.white.withOpacity(0.3)
                      : tile.accentColor;
                  return ListTile(
                    key: ValueKey(tile.id),
                    leading: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: accent.withOpacity(0.15),
                        border: Border.all(color: accent.withOpacity(0.25)),
                      ),
                      child: Icon(tile.icon, size: 18, color: accent),
                    ),
                    title: Text(
                      tile.label,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    trailing: Icon(
                      Icons.drag_handle_rounded,
                      color: AppColors.textMuted,
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  void _save() {
    ref.read(settingsProvider.notifier).update(
      ref.read(settingsProvider).copyWith(
        tileOrder: _tiles.map((t) => t.id).toList(),
      ),
    );
    Navigator.pop(context);
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _DraggableMobFab extends ConsumerStatefulWidget {
  const _DraggableMobFab();

  @override
  ConsumerState<_DraggableMobFab> createState() => _DraggableMobFabState();
}

class _DraggableMobFabState extends ConsumerState<_DraggableMobFab> {
  Offset? _pos; // null = use default bottom-right

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final s = ref.watch(stringsProvider);
    final isMobActive = ref.watch(mobProvider).isMobActive;

    // Default position: bottom-right
    final pos = _pos ?? Offset(size.width - 100, size.height - 160);

    // Clamp to screen bounds
    final clamped = Offset(
      pos.dx.clamp(0, size.width - 80),
      pos.dy.clamp(0, size.height - 80),
    );

    if (isMobActive) return const SizedBox.shrink(); // hide when MOB active

    return Positioned(
      left: clamped.dx,
      top: clamped.dy,
      child: _MobButton(
        label: s.mob,
        onTrigger: () => _triggerMob(context),
        onNavigate: () => context.push('/mob'),
        onDrag: (delta) {
          final cur = _pos ?? Offset(size.width - 100, size.height - 160);
          setState(() => _pos = Offset(
                cur.dx + delta.dx,
                cur.dy + delta.dy,
              ));
        },
      ),
    );
  }

  void _triggerMob(BuildContext context) {
    ref.read(mobProvider.notifier).trigger();
    context.push('/mob');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MOB Button — press-and-hold 1.2 s, spring scale, progress ring, haptics
// ─────────────────────────────────────────────────────────────────────────────

class _MobButton extends StatefulWidget {
  final String label;
  final VoidCallback onTrigger;
  final VoidCallback onNavigate;
  final void Function(Offset delta) onDrag;
  const _MobButton({
    required this.label,
    required this.onTrigger,
    required this.onNavigate,
    required this.onDrag,
  });

  @override
  State<_MobButton> createState() => _MobButtonState();
}

class _MobButtonState extends State<_MobButton>
    with TickerProviderStateMixin {
  static const _holdDuration = Duration(milliseconds: 1200);
  /// Minimum hold before a release counts as "navigate" tap.
  /// Must hold at least this long (until after vibration) to navigate.
  static const _minTapDuration = Duration(milliseconds: 150);
  /// Movement threshold to switch from press to drag (logical pixels).
  static const _dragThreshold = 8.0;

  late AnimationController _holdCtrl;   // 0→1 over holdDuration while pressing
  late AnimationController _scaleCtrl;  // spring-bounce on release
  late Animation<double> _scaleAnim;

  Timer? _triggerTimer;
  DateTime? _pressStartTime;
  bool _isDragging = false;
  bool _triggered = false;
  Offset _startPos = Offset.zero;

  @override
  void initState() {
    super.initState();

    _holdCtrl = AnimationController(vsync: this, duration: _holdDuration);

    _scaleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 1.0).animate(
      CurvedAnimation(parent: _scaleCtrl, curve: Curves.elasticOut),
    );
  }

  @override
  void dispose() {
    _holdCtrl.dispose();
    _scaleCtrl.dispose();
    _triggerTimer?.cancel();
    super.dispose();
  }

  void _onPanDown(DragDownDetails d) {
    _startPos = d.globalPosition;
    _isDragging = false;
    _triggered = false;
    _pressStartTime = DateTime.now();
    HapticFeedback.lightImpact();
    _holdCtrl.forward(from: 0);

    // Compress scale slightly while holding
    _scaleAnim = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(parent: _scaleCtrl, curve: Curves.elasticOut),
    );
    _scaleCtrl.value = 0; // start compressed
    _scaleCtrl.forward();

    // Schedule trigger at end of hold
    _triggerTimer = Timer(_holdDuration, () {
      _triggerTimer = null;
      _triggered = true;
      HapticFeedback.heavyImpact();
      _holdCtrl.reset();
      widget.onTrigger();
    });
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_triggered) return;
    final dist = (d.globalPosition - _startPos).distance;
    if (!_isDragging && dist > _dragThreshold) {
      _isDragging = true;
      // Cancel hold timer — we're dragging now
      _triggerTimer?.cancel();
      _triggerTimer = null;
      _holdCtrl.stop();
      _holdCtrl.reset();
    }
    if (_isDragging) {
      widget.onDrag(d.delta);
    }
  }

  void _onPanEnd(DragEndDetails _) {
    _triggerTimer?.cancel();
    _triggerTimer = null;
    _holdCtrl.stop();
    _holdCtrl.reset();

    // Spring-bounce back to full size
    _scaleAnim = Tween<double>(begin: _scaleCtrl.value * 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _scaleCtrl, curve: Curves.elasticOut),
    );
    _scaleCtrl.forward(from: 0);

    // Navigate on tap only if: not dragging, not already triggered,
    // and held at least _minTapDuration (waited for vibration feedback).
    if (!_isDragging && !_triggered && _pressStartTime != null) {
      final held = DateTime.now().difference(_pressStartTime!);
      if (held >= _minTapDuration) {
        widget.onNavigate();
      }
    }
    _isDragging = false;
    _pressStartTime = null;
  }

  void _onPanCancel() {
    _triggerTimer?.cancel();
    _triggerTimer = null;
    _holdCtrl.stop();
    _holdCtrl.reset();
    _isDragging = false;
    _pressStartTime = null;

    _scaleAnim = Tween<double>(begin: _scaleCtrl.value * 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _scaleCtrl, curve: Curves.elasticOut),
    );
    _scaleCtrl.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      dragStartBehavior: DragStartBehavior.down,
      onPanDown: _onPanDown,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      onPanCancel: _onPanCancel,
      child: AnimatedBuilder(
        animation: Listenable.merge([_holdCtrl, _scaleCtrl]),
        builder: (context, _) {
          final progress = _holdCtrl.value;
          final scale = _scaleAnim.value;

          return Transform.scale(
            scale: scale,
            child: SizedBox(
              width: 72,
              height: 72,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // ── Progress ring ──────────────────────────────────
                  SizedBox(
                    width: 72,
                    height: 72,
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 3.5,
                      backgroundColor: AppColors.danger.withOpacity(0.2),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          AppColors.danger),
                    ),
                  ),

                  // ── Core circle ────────────────────────────────────
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.danger
                          .withOpacity(0.75 + progress * 0.25),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.danger
                              .withOpacity(0.35 + progress * 0.4),
                          blurRadius: 18 + progress * 12,
                          spreadRadius: -2,
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: BackdropFilter(
                        filter:
                            ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.person_off_rounded,
                                size: 20, color: Colors.white),
                            const SizedBox(height: 2),
                            Text(
                              widget.label,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
