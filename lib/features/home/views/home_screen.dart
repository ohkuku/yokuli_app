import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'dart:async';

import '../../../core/theme/app_colors.dart';
import '../../../core/providers/connection_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/vessel_provider.dart';
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
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final conn = ref.watch(connectionProvider);
    final vessel = ref.watch(vesselProvider);

    final tiles = _buildTiles(vessel, conn);
    final isTablet = MediaQuery.of(context).size.width > 600;
    final crossCount = isTablet ? 3 : 2;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _Header(now: _now, vesselName: settings.vesselName, conn: conn),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossCount,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.1,
                ),
                itemCount: tiles.length,
                itemBuilder: (context, index) {
                  final tile = tiles[index];
                  return AppTile(
                    data: tile,
                    onTap: () => context.push(tile.route),
                  );
                },
              ),
            ),
            const VesselStatusBar(),
          ],
        ),
      ),
      // MOB floating button
      floatingActionButton: _MobFab(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  List<AppTileData> _buildTiles(vessel, ConnectionState conn) {
    final sogStr = vessel.speedOverGround != null
        ? '${vessel.speedOverGround!.toStringAsFixed(1)} kn'
        : null;

    return [
      AppTileData(
        id: 'signalk',
        label: 'Signal K Hub',
        icon: Icons.hub_rounded,
        accentColor: AppColors.modSignalK,
        route: '/signalk',
        badge: conn.isSignalKConnected ? 'Connected' : 'Disconnected',
      ),
      AppTileData(
        id: 'dashboard',
        label: 'Dashboard',
        icon: Icons.dashboard_rounded,
        accentColor: AppColors.modDashboard,
        route: '/dashboard',
        badge: sogStr,
      ),
      AppTileData(
        id: 'power',
        label: 'Power',
        icon: Icons.bolt_rounded,
        accentColor: AppColors.modPower,
        route: '/power',
        badge: vessel.batteries.isNotEmpty
            ? '${vessel.batteries.values.first.voltage?.toStringAsFixed(1) ?? '—'} V'
            : null,
      ),
      AppTileData(
        id: 'logbook',
        label: 'Logbook',
        icon: Icons.auto_stories_rounded,
        accentColor: AppColors.modLogbook,
        route: '/logbook',
      ),
      AppTileData(
        id: 'safety',
        label: 'Safety',
        icon: Icons.emergency_rounded,
        accentColor: AppColors.modSafety,
        route: '/safety',
      ),
      AppTileData(
        id: 'maintenance',
        label: 'Maintenance',
        icon: Icons.build_rounded,
        accentColor: AppColors.modMaintenance,
        route: '/maintenance',
      ),
      AppTileData(
        id: 'weather',
        label: 'Weather',
        icon: Icons.cloud_rounded,
        accentColor: AppColors.modWeather,
        route: '/settings', // redirects to settings until implemented
        isStub: true,
      ),
      AppTileData(
        id: 'tools',
        label: 'Tools',
        icon: Icons.handyman_rounded,
        accentColor: AppColors.modTools,
        route: '/settings',
        isStub: true,
      ),
      AppTileData(
        id: 'settings',
        label: 'Settings',
        icon: Icons.settings_rounded,
        accentColor: AppColors.textSecondary,
        route: '/settings',
      ),
    ];
  }
}

class _Header extends StatelessWidget {
  final DateTime now;
  final String vesselName;
  final ConnectionState conn;

  const _Header({
    required this.now,
    required this.vesselName,
    required this.conn,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          // Vessel name + date
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  vesselName.toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.cyan,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2.0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  DateFormat('EEE d MMM  HH:mm:ss').format(now),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          // Connection status icons
          _connIcon(
            icon: Icons.hub_rounded,
            active: conn.isSignalKConnected,
            tooltip: 'Signal K',
            color: AppColors.cyan,
          ),
          const SizedBox(width: 8),
          _connIcon(
            icon: Icons.wifi_rounded,
            active: conn.isLanSyncActive,
            tooltip: 'LAN Sync (${conn.connectedPeers.length} peers)',
            color: AppColors.teal,
          ),
        ],
      ),
    );
  }

  Widget _connIcon({
    required IconData icon,
    required bool active,
    required String tooltip,
    required Color color,
  }) {
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: active ? color.withAlpha(28) : AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? color.withAlpha(80) : AppColors.border,
          ),
        ),
        child: Icon(icon, size: 17, color: active ? color : AppColors.inactive),
      ),
    );
  }
}

class _MobFab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FloatingActionButton.extended(
      onPressed: () => _confirmMob(context, ref),
      backgroundColor: AppColors.danger,
      foregroundColor: Colors.white,
      icon: const Icon(Icons.person_off_rounded),
      label: const Text(
        'MOB',
        style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1),
      ),
      elevation: 6,
    );
  }

  void _confirmMob(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.dialogBg,
        title: const Row(
          children: [
            Icon(Icons.warning_rounded, color: AppColors.danger),
            SizedBox(width: 8),
            Text('MAN OVERBOARD', style: TextStyle(color: AppColors.danger)),
          ],
        ),
        content: const Text(
          'Trigger a Man Overboard alert?\n\nThis will record your current GPS position and notify all connected devices.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () {
              Navigator.pop(context);
              context.push('/safety');
              // MOB trigger is handled in SafetyScreen
            },
            child: const Text('CONFIRM MOB'),
          ),
        ],
      ),
    );
  }
}
