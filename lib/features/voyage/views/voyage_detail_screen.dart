import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/providers/voyage_provider.dart';
import '../../../core/providers/log_provider.dart';
import '../../../core/models/voyage.dart';
import '../../../core/models/log_entry.dart';

// ---------------------------------------------------------------------------
// VoyageDetailScreen
// ---------------------------------------------------------------------------

class VoyageDetailScreen extends ConsumerStatefulWidget {
  final String voyageId;
  const VoyageDetailScreen({super.key, required this.voyageId});

  @override
  ConsumerState<VoyageDetailScreen> createState() => _VoyageDetailScreenState();
}

class _VoyageDetailScreenState extends ConsumerState<VoyageDetailScreen> {
  // ---- Edit helpers --------------------------------------------------------

  Future<void> _editName(VoyageSession voyage) async {
    final controller = TextEditingController(text: voyage.name ?? '');
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        title: const Text('航行名称',
            style: TextStyle(color: AppColors.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(
            hintText: '输入自定义名称',
            hintStyle: TextStyle(color: AppColors.textMuted),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.border),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.cyan),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('保存',
                style: TextStyle(color: AppColors.cyan)),
          ),
        ],
      ),
    );
    if (result != null) {
      await ref.read(voyageProvider.notifier).rename(voyage.id, result);
    }
  }

  Future<void> _editNotes(VoyageSession voyage) async {
    final controller = TextEditingController(text: voyage.notes ?? '');
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        title: const Text('航行备注',
            style: TextStyle(color: AppColors.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 6,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(
            hintText: '记录这次航行的感受、路线或其他信息…',
            hintStyle: TextStyle(color: AppColors.textMuted),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: AppColors.cyan),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('保存',
                style: TextStyle(color: AppColors.cyan)),
          ),
        ],
      ),
    );
    if (result != null) {
      await ref.read(voyageProvider.notifier).updateNotes(voyage.id, result);
    }
  }

  // ---- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final voyageState = ref.watch(voyageProvider);
    final allLogs = ref.watch(logProvider);

    // Find the voyage (active or history)
    VoyageSession? voyage = voyageState.active?.id == widget.voyageId
        ? voyageState.active
        : null;
    voyage ??= voyageState.history
        .cast<VoyageSession?>()
        .firstWhere((v) => v?.id == widget.voyageId, orElse: () => null);

    if (voyage == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          iconTheme: const IconThemeData(color: AppColors.textPrimary),
          title: const Text('航行详情',
              style: TextStyle(color: AppColors.textPrimary)),
        ),
        body: const Center(
          child: Text('航行记录不存在',
              style: TextStyle(color: AppColors.textMuted)),
        ),
      );
    }

    // Log entries belonging to this voyage, newest-first
    final voyageLogs = allLogs
        .where((e) => e.voyageId == widget.voyageId)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    // Collect positions for map
    final positions = <LatLng>[];
    if (voyage.startPosition != null) {
      positions.add(LatLng(voyage.startPosition!.latitude,
          voyage.startPosition!.longitude));
    }
    for (final entry in voyageLogs.reversed) {
      final pos = entry.context?.position;
      if (pos != null) {
        positions.add(LatLng(pos.latitude, pos.longitude));
      }
    }
    if (voyage.endPosition != null) {
      positions.add(
          LatLng(voyage.endPosition!.latitude, voyage.endPosition!.longitude));
    }

    final dur = voyage.duration;
    final h = dur.inHours;
    final m = dur.inMinutes % 60;
    final durationStr = voyage.isActive
        ? '进行中'
        : (h > 0 ? '${h}h ${m}m' : '${m}m');

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: GestureDetector(
          onTap: () => _editName(voyage!),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  voyage.displayTitle,
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 17),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.edit_rounded,
                  size: 14, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // ---- Summary card ----
          _SummaryCard(voyage: voyage, durationStr: durationStr),
          const SizedBox(height: 12),

          // ---- Notes ----
          _NotesCard(voyage: voyage, onEdit: () => _editNotes(voyage!)),
          const SizedBox(height: 16),

          // ---- Map ----
          if (positions.isNotEmpty) ...[
            const _SectionLabel('航迹地图'),
            const SizedBox(height: 8),
            _VoyageMap(positions: positions),
            const SizedBox(height: 16),
          ],

          // ---- Log entries ----
          _SectionLabel('记录 (${voyageLogs.length})'),
          const SizedBox(height: 8),
          if (voyageLogs.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text('暂无记录',
                    style:
                        TextStyle(color: AppColors.textMuted, fontSize: 13)),
              ),
            )
          else
            ...voyageLogs.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _LogEntryCard(
                  entry: entry,
                  onTap: () => _showLogDetail(context, entry),
                ),
              ),
            ),
        ],
      ),
    );
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
}

// ---------------------------------------------------------------------------
// Summary Card
// ---------------------------------------------------------------------------

class _SummaryCard extends StatelessWidget {
  final VoyageSession voyage;
  final String durationStr;
  const _SummaryCard({required this.voyage, required this.durationStr});

  @override
  Widget build(BuildContext context) {
    final startFmt =
        DateFormat('dd MMM yyyy  HH:mm').format(voyage.startTime.toLocal());
    final endFmt = voyage.endTime != null
        ? DateFormat('dd MMM yyyy  HH:mm').format(voyage.endTime!.toLocal())
        : '—';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          _Row(icon: Icons.play_arrow_rounded, label: '出发', value: startFmt),
          const SizedBox(height: 8),
          _Row(icon: Icons.stop_rounded, label: '到港', value: endFmt),
          const SizedBox(height: 8),
          _Row(
              icon: Icons.timer_outlined,
              label: '时长',
              value: durationStr),
          const SizedBox(height: 8),
          _Row(
            icon: Icons.sailing_rounded,
            label: '来源',
            value: voyage.source == VoyageSource.auto ? '自动检测' : '手动',
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _Row({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.textMuted),
        const SizedBox(width: 8),
        SizedBox(
          width: 42,
          child: Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12)),
        ),
        Expanded(
          child: Text(value,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Notes Card
// ---------------------------------------------------------------------------

class _NotesCard extends StatelessWidget {
  final VoyageSession voyage;
  final VoidCallback onEdit;
  const _NotesCard({required this.voyage, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final hasNotes = voyage.notes != null && voyage.notes!.isNotEmpty;
    return GestureDetector(
      onTap: onEdit,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.notes_rounded, size: 16, color: AppColors.teal),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                hasNotes ? voyage.notes! : '点击添加航行备注…',
                style: TextStyle(
                  color:
                      hasNotes ? AppColors.textPrimary : AppColors.textMuted,
                  fontSize: 13,
                ),
              ),
            ),
            const Icon(Icons.edit_rounded, size: 14, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Voyage Map
// ---------------------------------------------------------------------------

class _VoyageMap extends StatelessWidget {
  final List<LatLng> positions;
  const _VoyageMap({required this.positions});

  @override
  Widget build(BuildContext context) {
    // Compute bounds
    double minLat = positions.first.latitude;
    double maxLat = positions.first.latitude;
    double minLon = positions.first.longitude;
    double maxLon = positions.first.longitude;
    for (final p in positions) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLon) minLon = p.longitude;
      if (p.longitude > maxLon) maxLon = p.longitude;
    }
    final centerLat = (minLat + maxLat) / 2;
    final centerLon = (minLon + maxLon) / 2;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 220,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: LatLng(centerLat, centerLon),
            initialZoom: 12,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'app.yokuli',
            ),
            if (positions.length > 1)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: positions,
                    color: AppColors.cyan.withAlpha(220),
                    strokeWidth: 2.5,
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                // Start marker (green)
                Marker(
                  point: positions.first,
                  width: 22,
                  height: 22,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.success,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
                // End marker (red) if different from start
                if (positions.length > 1)
                  Marker(
                    point: positions.last,
                    width: 22,
                    height: 22,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.danger,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                // Intermediate log entry positions (cyan dots)
                ...positions
                    .sublist(
                        1, positions.length > 1 ? positions.length - 1 : 1)
                    .map(
                      (p) => Marker(
                        point: p,
                        width: 10,
                        height: 10,
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.cyan,
                            shape: BoxShape.circle,
                            border:
                                Border.all(color: Colors.white, width: 1.5),
                          ),
                        ),
                      ),
                    ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Log Entry Card (inside voyage detail)
// ---------------------------------------------------------------------------

class _LogEntryCard extends StatelessWidget {
  final LogEntry entry;
  final VoidCallback onTap;
  const _LogEntryCard({required this.entry, required this.onTap});

  static const _typeConfig = <LogEntryType, ({IconData icon, Color color})>{
    LogEntryType.system: (icon: Icons.settings_rounded, color: AppColors.inactive),
    LogEntryType.alarm: (icon: Icons.warning_rounded, color: AppColors.danger),
    LogEntryType.navigation: (icon: Icons.navigation_rounded, color: AppColors.cyan),
    LogEntryType.power: (icon: Icons.bolt_rounded, color: AppColors.warning),
    LogEntryType.ais: (icon: Icons.directions_boat_rounded, color: Color(0xFF0A84FF)),
    LogEntryType.manual: (icon: Icons.edit_note_rounded, color: AppColors.teal),
    LogEntryType.maintenance: (icon: Icons.build_rounded, color: Color(0xFFFF9F0A)),
  };

  @override
  Widget build(BuildContext context) {
    final cfg = _typeConfig[entry.type] ??
        (icon: Icons.info_outline_rounded, color: AppColors.textMuted);
    final timeFmt = DateFormat('HH:mm').format(entry.timestamp.toLocal());
    final hasPos = entry.context?.position != null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: cfg.color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(cfg.icon, size: 16, color: cfg.color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.message,
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 13),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(timeFmt,
                          style: const TextStyle(
                              color: AppColors.textMuted, fontSize: 11)),
                      if (hasPos) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.location_on_rounded,
                            size: 11, color: AppColors.textMuted),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                size: 16, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Log Detail Sheet — full snapshot + map pin
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
            const _SheetSectionHeader('导航'),
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
            if (ctx.trueWindSpeed != null || ctx.trueWindDirection != null) ...[
              const SizedBox(height: 6),
              const _SheetSectionHeader('风'),
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
              const _SheetSectionHeader('电力'),
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

class _SheetSectionHeader extends StatelessWidget {
  final String text;
  const _SheetSectionHeader(this.text);

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

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
        ),
      );
}
