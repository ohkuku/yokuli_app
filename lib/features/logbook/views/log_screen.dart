import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/providers/log_provider.dart';
import '../../../core/providers/voyage_provider.dart';
import '../../../core/providers/locale_provider.dart';
import '../../../core/models/log_entry.dart';
import '../../../core/l10n/strings.dart';

// ---------------------------------------------------------------------------
// Tab category definition
// ---------------------------------------------------------------------------

typedef _TabCategory = ({String label, List<LogEntryType> types});

// empty types list = show all
const List<_TabCategory> _kTabs = [
  (label: '全部', types: []),
  (label: '航行', types: [LogEntryType.navigation]),
  (label: '安全', types: [LogEntryType.system, LogEntryType.alarm]),
  (label: '维保', types: [LogEntryType.maintenance]),
  (label: '手动', types: [LogEntryType.manual]),
];

// ---------------------------------------------------------------------------
// LogScreen
// ---------------------------------------------------------------------------

class LogScreen extends ConsumerStatefulWidget {
  const LogScreen({super.key});

  @override
  ConsumerState<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends ConsumerState<LogScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _kTabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<LogEntry> _filter(List<LogEntry> all, List<LogEntryType> types) {
    final entries = types.isEmpty
        ? List<LogEntry>.from(all)
        : all.where((e) => types.contains(e.type)).toList();
    entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return entries;
  }

  void _showLogDetail(BuildContext context, LogEntry entry) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _LogDetailSheet(entry: entry),
    );
  }

  void _showManualLogDialog(S s) {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        title: Text(s.addLogEntry,
            style: const TextStyle(color: AppColors.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: s.enterMessage,
            hintStyle: const TextStyle(color: AppColors.textMuted),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.border),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.cyan),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.cancel,
                style: const TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              final text = controller.text.trim();
              Navigator.pop(ctx);
              if (text.isNotEmpty) {
                ref.read(logProvider.notifier).log(
                      type: LogEntryType.manual,
                      message: text,
                    );
              }
            },
            child: Text(s.add, style: const TextStyle(color: AppColors.cyan)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(S s) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.subject_rounded,
                size: 56, color: AppColors.inactive),
            const SizedBox(height: 14),
            Text(
              s.noLogEntries,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              s.noLogEntriesHint,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(
      BuildContext context, List<LogEntry> entries, S s) {
    final voyageNames = ref.watch(voyageNameMapProvider);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final entry = entries[index];
        return _LogEntryRow(
          entry: entry,
          voyageName:
              entry.voyageId != null ? voyageNames[entry.voyageId] : null,
          onTap: () => _showLogDetail(context, entry),
          onVoyageTap: entry.voyageId != null
              ? () => context.push('/voyage/${entry.voyageId}')
              : null,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final allEntries = ref.watch(logProvider).where((e) => !e.deleted).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text(s.logTitle,
            style: const TextStyle(color: AppColors.textPrimary)),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: AppColors.cyan,
          labelColor: AppColors.cyan,
          unselectedLabelColor: AppColors.textSecondary,
          labelStyle: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600),
          unselectedLabelStyle:
              const TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
          dividerColor: AppColors.border,
          tabs: _kTabs.map((t) => Tab(text: t.label)).toList(),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.teal,
        foregroundColor: AppColors.background,
        onPressed: () => _showManualLogDialog(s),
        child: const Icon(Icons.edit_rounded),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _kTabs.map((category) {
          final filtered = _filter(allEntries, category.types);
          if (filtered.isEmpty) return _buildEmpty(s);
          return _buildList(context, filtered, s);
        }).toList(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Log Entry Row
// ---------------------------------------------------------------------------

class _LogEntryRow extends StatelessWidget {
  final LogEntry entry;
  final String? voyageName;
  final VoidCallback onTap;
  final VoidCallback? onVoyageTap;

  const _LogEntryRow({
    required this.entry,
    this.voyageName,
    required this.onTap,
    this.onVoyageTap,
  });

  static const _typeConfig = <LogEntryType, ({IconData icon, Color color})>{
    LogEntryType.system: (
      icon: Icons.settings_rounded,
      color: AppColors.inactive,
    ),
    LogEntryType.alarm: (
      icon: Icons.warning_rounded,
      color: AppColors.danger,
    ),
    LogEntryType.navigation: (
      icon: Icons.navigation_rounded,
      color: AppColors.cyan,
    ),
    LogEntryType.power: (
      icon: Icons.bolt_rounded,
      color: AppColors.warning,
    ),
    LogEntryType.ais: (
      icon: Icons.directions_boat_rounded,
      color: Color(0xFF0A84FF),
    ),
    LogEntryType.manual: (
      icon: Icons.edit_note_rounded,
      color: AppColors.teal,
    ),
    LogEntryType.maintenance: (
      icon: Icons.build_rounded,
      color: Color(0xFFFF9F0A),
    ),
  };

  static Color _bgColor(LogEntryType type) {
    switch (type) {
      case LogEntryType.alarm:
        return AppColors.danger.withAlpha(10);
      case LogEntryType.navigation:
        return AppColors.cyan.withAlpha(8);
      case LogEntryType.power:
        return AppColors.warning.withAlpha(8);
      case LogEntryType.ais:
        return const Color(0xFF0A84FF).withAlpha(8);
      case LogEntryType.manual:
        return AppColors.teal.withAlpha(8);
      default:
        return AppColors.cardBg;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = _typeConfig[entry.type] ??
        (icon: Icons.info_outline_rounded, color: AppColors.textMuted);
    final timeFmt =
        DateFormat('HH:mm dd/MM').format(entry.timestamp.toLocal());

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _bgColor(entry.type),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Icon
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: cfg.color.withAlpha(25),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(cfg.icon, size: 17, color: cfg.color),
            ),
            const SizedBox(width: 12),
            // Message + subtype + voyage chip
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    entry.message,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (entry.subtype != null && entry.subtype!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      entry.subtype!,
                      style: TextStyle(
                        color: cfg.color,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (voyageName != null) ...[
                    const SizedBox(height: 3),
                    GestureDetector(
                      onTap: onVoyageTap,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.teal.withAlpha(28),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: AppColors.teal.withAlpha(80)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.sailing_rounded,
                                size: 10, color: AppColors.teal),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                voyageName!,
                                style: const TextStyle(
                                  color: AppColors.teal,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Timestamp
            Text(
              timeFmt,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Log Detail Sheet — full snapshot + optional map pin
// ---------------------------------------------------------------------------

class _LogDetailSheet extends StatelessWidget {
  final LogEntry entry;
  const _LogDetailSheet({required this.entry});

  @override
  Widget build(BuildContext context) {
    final ctx = entry.context;
    final timeFmt =
        DateFormat('dd MMM yyyy  HH:mm:ss').format(entry.timestamp.toLocal());

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollController) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.inactive,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(entry.message,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(timeFmt,
              style: const TextStyle(
                  color: AppColors.textMuted, fontSize: 12)),
          const SizedBox(height: 14),

          // ---- Map pin (if we have a position) ----
          if (ctx?.position != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                height: 180,
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: LatLng(ctx!.position!.latitude,
                        ctx.position!.longitude),
                    initialZoom: 14,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.none,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'app.yokuli',
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: LatLng(ctx.position!.latitude,
                              ctx.position!.longitude),
                          width: 24,
                          height: 24,
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.cyan,
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: Colors.white, width: 2.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],

          if (ctx != null) ...[
            const Divider(color: AppColors.border),
            const SizedBox(height: 10),
            _SheetSection('导航'),
            if (ctx.position != null)
              _DetailRow(
                icon: Icons.location_on_rounded,
                label: '坐标',
                value:
                    '${ctx.position!.latitude.toStringAsFixed(5)}°, '
                    '${ctx.position!.longitude.toStringAsFixed(5)}°',
              ),
            if (ctx.sog != null)
              _DetailRow(
                  icon: Icons.speed_rounded,
                  label: 'SOG',
                  value: '${ctx.sog!.toStringAsFixed(1)} kn'),
            if (ctx.cog != null)
              _DetailRow(
                  icon: Icons.explore_rounded,
                  label: 'COG',
                  value: '${ctx.cog!.toStringAsFixed(0)}°'),
            if (ctx.heading != null)
              _DetailRow(
                  icon: Icons.navigation_rounded,
                  label: 'HDG',
                  value: '${ctx.heading!.toStringAsFixed(0)}°'),
            if (ctx.depth != null)
              _DetailRow(
                  icon: Icons.water_rounded,
                  label: '龙骨下水深',
                  value: '${ctx.depth!.toStringAsFixed(1)} m'),
            if (ctx.depthBelowSurface != null)
              _DetailRow(
                  icon: Icons.water_rounded,
                  label: '水面水深',
                  value: '${ctx.depthBelowSurface!.toStringAsFixed(1)} m'),
            if (ctx.trueWindSpeed != null ||
                ctx.trueWindDirection != null ||
                ctx.apparentWindSpeed != null) ...[
              const SizedBox(height: 6),
              _SheetSection('风'),
            ],
            if (ctx.trueWindSpeed != null)
              _DetailRow(
                  icon: Icons.air_rounded,
                  label: '真风速',
                  value: '${ctx.trueWindSpeed!.toStringAsFixed(1)} kn'),
            if (ctx.trueWindDirection != null)
              _DetailRow(
                  icon: Icons.air_rounded,
                  label: '真风向',
                  value: '${ctx.trueWindDirection!.toStringAsFixed(0)}°'),
            if (ctx.apparentWindSpeed != null)
              _DetailRow(
                  icon: Icons.air_rounded,
                  label: '表风速',
                  value: '${ctx.apparentWindSpeed!.toStringAsFixed(1)} kn'),
            if (ctx.apparentWindAngle != null)
              _DetailRow(
                  icon: Icons.air_rounded,
                  label: '表风角',
                  value: '${ctx.apparentWindAngle!.toStringAsFixed(0)}°'),
            if (ctx.allBatteryVoltages.isNotEmpty ||
                ctx.solarPower != null) ...[
              const SizedBox(height: 6),
              _SheetSection('电力'),
            ],
            ...ctx.allBatteryVoltages.entries.map(
              (e) => _DetailRow(
                  icon: Icons.battery_full_rounded,
                  label: e.key,
                  value: '${e.value.toStringAsFixed(2)} V'),
            ),
            if (ctx.solarPower != null)
              _DetailRow(
                  icon: Icons.wb_sunny_rounded,
                  label: '太阳能',
                  value: '${ctx.solarPower!.toStringAsFixed(0)} W'),
          ],
        ],
      ),
    );
  }
}

class _SheetSection extends StatelessWidget {
  final String text;
  const _SheetSection(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
          ),
        ),
      );
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _DetailRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Icon(icon, size: 14, color: AppColors.textMuted),
            const SizedBox(width: 8),
            SizedBox(
              width: 70,
              child: Text('$label:',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13)),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      );
}
