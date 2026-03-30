import 'dart:async';
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
import '../../../core/providers/alarm_provider.dart';
import '../../../core/providers/kanban_provider.dart';
import '../../../features/safety/providers/safety_provider.dart';
import '../../../core/services/update/update_dialog.dart';
import '../../../core/widgets/glass_card.dart';
import '../widgets/app_tile.dart';
import '../widgets/vessel_status_bar.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late Timer _clockTimer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showUpdateDialogIfNeeded(context);
    });
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final conn    = ref.watch(connectionProvider);
    final vessel  = ref.watch(vesselProvider);
    final s       = ref.watch(stringsProvider);

    final alarmCount  = ref.watch(activeAlarmCountProvider);
    final kanbanCount = ref.watch(kanbanProvider).cards.length;

    var tiles = _buildTiles(vessel, conn, s, alarmCount, kanbanCount);

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
          // ── Aurora background ──────────────────────────────────────
          const Positioned.fill(child: AuroraBackground()),

          // ── Content ───────────────────────────────────────────────
          SafeArea(
            child: Column(
              children: [
                _Header(
                  now: _now,
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
  ) {
    final sogStr = vessel.speedOverGround != null
        ? '${vessel.speedOverGround!.toStringAsFixed(1)} kn'
        : null;

    final signalKBadge = conn.isSignalKConnected ? s.connected : s.disconnected;

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
        label: s.safety,
        icon: Icons.emergency_rounded,
        accentColor: AppColors.modSafety,
        route: '/safety',
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

class _Header extends ConsumerWidget {
  final DateTime now;
  final String vesselName;
  final AppConnectionState conn;
  final VoidCallback? onArrange;

  const _Header({
    required this.now,
    required this.vesselName,
    required this.conn,
    this.onArrange,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                  Text(
                    vesselName.toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.cyan,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.5,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    DateFormat('EEE d MMM  HH:mm:ss').format(now),
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
              active: conn.isSignalKConnected,
              color: AppColors.cyan,
              label: 'SK',
            ),
            const SizedBox(width: 8),
            _ConnBadge(
              icon: Icons.wifi_rounded,
              active: conn.isLanSyncActive,
              color: AppColors.teal,
              label: conn.isLanSyncActive && conn.peerCount > 0
                  ? 'LAN ×${conn.peerCount}'
                  : 'LAN',
            ),
            const SizedBox(width: 8),
            // Notification bell
            _NotificationBell(),
            const SizedBox(width: 8),
            // Arrange tiles button
            GestureDetector(
              onTap: onArrange,
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
// Notification bell with badge
// ─────────────────────────────────────────────────────────────────────────────

class _NotificationBell extends ConsumerWidget {
  const _NotificationBell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(activeAlarmCountProvider);

    return GestureDetector(
      onTap: () => context.push('/notifications'),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: count > 0
                  ? AppColors.danger.withOpacity(0.15)
                  : Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: count > 0
                      ? AppColors.danger.withOpacity(0.35)
                      : Colors.white.withOpacity(0.10)),
            ),
            child: Icon(
              count > 0
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_rounded,
              size: 14,
              color: count > 0
                  ? AppColors.danger
                  : Colors.white.withOpacity(0.4),
            ),
          ),
          if (count > 0)
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.danger,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.background, width: 1),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w800),
                ),
              ),
            ),
        ],
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
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final s = ref.watch(stringsProvider);
    final isMobActive = ref.watch(safetyProvider).isMobActive;

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
      child: GestureDetector(
        // DragStartBehavior.down = tracking starts from first touch, not after threshold
        dragStartBehavior: DragStartBehavior.down,
        onPanStart: (_) => setState(() => _isDragging = true),
        onPanUpdate: (d) {
          // Use _pos directly (always current) rather than the closure-captured
          // `clamped`, which is stale when multiple events fire before a rebuild.
          final cur = _pos ?? Offset(size.width - 100, size.height - 160);
          setState(() => _pos = Offset(
                cur.dx + d.delta.dx,
                cur.dy + d.delta.dy,
              ));
        },
        onPanEnd: (_) => setState(() => _isDragging = false),
        child: _MobButton(
          label: s.mob,
          isDragging: _isDragging,
          onTrigger: () => _triggerMob(context),
        ),
      ),
    );
  }

  void _triggerMob(BuildContext context) {
    ref.read(safetyProvider.notifier).triggerMob();
    context.push('/safety');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MOB Button — press-and-hold 1.2 s, spring scale, progress ring, haptics
// ─────────────────────────────────────────────────────────────────────────────

class _MobButton extends StatefulWidget {
  final String label;
  final bool isDragging;
  final VoidCallback onTrigger;
  const _MobButton({
    required this.label,
    required this.isDragging,
    required this.onTrigger,
  });

  @override
  State<_MobButton> createState() => _MobButtonState();
}

class _MobButtonState extends State<_MobButton>
    with TickerProviderStateMixin {
  static const _holdDuration = Duration(milliseconds: 1200);

  late AnimationController _holdCtrl;   // 0→1 over holdDuration while pressing
  late AnimationController _scaleCtrl;  // spring-bounce on release
  late Animation<double> _scaleAnim;

  Timer? _triggerTimer;

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

  void _onPressStart() {
    if (widget.isDragging) return;
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
      HapticFeedback.heavyImpact();
      _holdCtrl.reset();
      widget.onTrigger();
    });
  }

  void _onPressEnd() {
    _triggerTimer?.cancel();
    _triggerTimer = null;
    _holdCtrl.stop();
    _holdCtrl.reset();

    // Spring-bounce back to full size
    _scaleAnim = Tween<double>(begin: _scaleCtrl.value * 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _scaleCtrl, curve: Curves.elasticOut),
    );
    _scaleCtrl.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _onPressStart(),
      onTapUp: (_) => _onPressEnd(),
      onTapCancel: _onPressEnd,
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
