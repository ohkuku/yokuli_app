import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/providers/connection_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/vessel_provider.dart';
import '../../../core/providers/locale_provider.dart';
import '../../../core/providers/alarm_provider.dart';
import '../../../core/providers/task_provider.dart';
import '../../../core/providers/issue_provider.dart';
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
    final taskCount   = ref.watch(openTasksProvider).length;
    final issueCount  = ref.watch(openIssuesProvider).length;

    var tiles = _buildTiles(vessel, conn, s, alarmCount, taskCount, issueCount);

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
        ],
      ),
      floatingActionButton: _MobFab(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  List<AppTileData> _buildTiles(
    vessel,
    AppConnectionState conn,
    s,
    int alarmCount,
    int taskCount,
    int issueCount,
  ) {
    final sogStr = vessel.speedOverGround != null
        ? '${vessel.speedOverGround!.toStringAsFixed(1)} kn'
        : null;

    return [
      AppTileData(
        id: 'signalk',
        label: s.signalKHub,
        icon: Icons.hub_rounded,
        accentColor: AppColors.modSignalK,
        route: '/signalk',
        badge: conn.isSignalKConnected ? s.connected : s.disconnected,
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
        id: 'logbook',
        label: s.logbook,
        icon: Icons.auto_stories_rounded,
        accentColor: AppColors.modLogbook,
        route: '/logbook',
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
        id: 'maintenance',
        label: s.maintenance,
        icon: Icons.build_rounded,
        accentColor: AppColors.modMaintenance,
        route: '/maintenance',
      ),
      AppTileData(
        id: 'weather',
        label: s.weather,
        icon: Icons.cloud_rounded,
        accentColor: AppColors.modWeather,
        route: '/settings',
        isStub: true,
      ),
      AppTileData(
        id: 'tools',
        label: s.tools,
        icon: Icons.handyman_rounded,
        accentColor: AppColors.modTools,
        route: '/settings',
        isStub: true,
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
        id: 'tasks',
        label: s.tasksTitle,
        icon: Icons.checklist_rounded,
        accentColor: AppColors.success,
        route: '/tasks',
        notificationCount: taskCount,
      ),
      AppTileData(
        id: 'issues',
        label: s.issuesTitle,
        icon: Icons.bug_report_rounded,
        accentColor: AppColors.warning,
        route: '/issues',
        notificationCount: issueCount,
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

class _Header extends StatelessWidget {
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
  Widget build(BuildContext context) {
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
              label: 'LAN',
            ),
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

class _MobFab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.danger.withOpacity(0.45),
            blurRadius: 20,
            spreadRadius: -4,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger.withOpacity(0.85),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              elevation: 0,
            ),
            onPressed: () => _confirmMob(context, ref, s),
            icon: const Icon(Icons.person_off_rounded, size: 20),
            label: Text(
              s.mob,
              style: const TextStyle(
                  fontWeight: FontWeight.w800, letterSpacing: 1.5),
            ),
          ),
        ),
      ),
    );
  }

  void _confirmMob(BuildContext context, WidgetRef ref, s) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _MobDialog(s: s),
    );
  }
}

class _MobDialog extends StatelessWidget {
  final dynamic s;
  const _MobDialog({required this.s});

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
      child: AlertDialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        content: GlassCard(
          tint: AppColors.danger,
          opacity: 0.08,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.danger.withOpacity(0.18),
                  border: Border.all(
                      color: AppColors.danger.withOpacity(0.4), width: 1),
                ),
                child: const Icon(Icons.warning_rounded,
                    color: AppColors.danger, size: 28),
              ),
              const SizedBox(height: 16),
              Text(
                s.manOverboard,
                style: const TextStyle(
                  color: AppColors.danger,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                s.mobConfirmBody,
                style:
                    TextStyle(color: Colors.white.withOpacity(0.7), height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white.withOpacity(0.6),
                        side: BorderSide(color: Colors.white.withOpacity(0.2)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: Text(s.cancel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.danger,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        context.push('/safety');
                      },
                      child: Text(s.mobConfirm,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
