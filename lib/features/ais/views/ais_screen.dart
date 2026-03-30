import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/providers/ais_provider.dart';
import '../../../core/models/ais_state.dart';

class AisScreen extends ConsumerWidget {
  const AisScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('AIS'),
          bottom: const TabBar(
            indicatorColor: AppColors.cyan,
            labelColor: AppColors.cyan,
            unselectedLabelColor: AppColors.textSecondary,
            tabs: [
              Tab(text: 'Radar'),
              Tab(text: 'Nearby'),
              Tab(text: 'Risk'),
              Tab(text: 'Own Ship'),
            ],
          ),
        ),
        body: SafeArea(
          child: TabBarView(
            children: [
              _RadarTab(),
              _NearbyTab(),
              _RiskTab(),
              _OwnShipTab(),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Radar Tab
// ---------------------------------------------------------------------------

class _RadarTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aisState = ref.watch(aisProvider);
    final targets = aisState.targets;

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: AspectRatio(
              aspectRatio: 1,
              child: CustomPaint(
                painter: _AisRadarPainter(targets: targets),
                child: Container(),
              ),
            ),
          ),
        ),
        // Legend
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _LegendDot(color: AppColors.danger, label: 'High Risk (CPA<0.5NM)'),
              const SizedBox(width: 16),
              _LegendDot(color: AppColors.warning, label: 'Caution'),
              const SizedBox(width: 16),
              _LegendDot(color: AppColors.success, label: 'Clear'),
            ],
          ),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
      ],
    );
  }
}

class _AisRadarPainter extends CustomPainter {
  final List<AisTargetState> targets;

  const _AisRadarPainter({required this.targets});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;

    // Determine scale: fit the furthest target, min 3NM, max 20NM
    double maxDist = 3.0;
    for (final t in targets) {
      if (t.relativeDistanceNm != null && t.relativeDistanceNm! > maxDist) {
        maxDist = math.min(t.relativeDistanceNm!, 20.0);
      }
    }
    // Round up to a nice ring value
    final rangeNm = maxDist <= 3 ? 3.0 : maxDist <= 6 ? 6.0 : maxDist <= 10 ? 10.0 : 20.0;
    final scale = radius / rangeNm;

    // Background
    final bgPaint = Paint()..color = const Color(0xFF0A1A2F);
    canvas.drawCircle(center, radius, bgPaint);

    // Range rings
    final ringPaint = Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    final ringIntervals = rangeNm <= 3 ? [1.0, 2.0, 3.0]
        : rangeNm <= 6 ? [2.0, 4.0, 6.0]
        : rangeNm <= 10 ? [2.5, 5.0, 10.0]
        : [5.0, 10.0, 20.0];

    final labelStyle = TextStyle(
      color: Colors.white.withOpacity(0.3),
      fontSize: 9,
    );

    for (final nm in ringIntervals) {
      final r = nm * scale;
      canvas.drawCircle(center, r, ringPaint);
      // Ring label at top
      final nmLabel = nm == nm.roundToDouble() ? '${nm.toInt()}NM' : '${nm}NM';
      final tp = TextPainter(
        text: TextSpan(text: nmLabel, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - r + 2));
    }

    // Cardinal lines (N/S/E/W)
    final linePaint = Paint()
      ..color = Colors.white.withOpacity(0.07)
      ..strokeWidth = 0.6;
    canvas.drawLine(Offset(center.dx, center.dy - radius),
        Offset(center.dx, center.dy + radius), linePaint);
    canvas.drawLine(Offset(center.dx - radius, center.dy),
        Offset(center.dx + radius, center.dy), linePaint);

    // Compass labels
    final compassStyle = TextStyle(
      color: Colors.white.withOpacity(0.4),
      fontSize: 10,
      fontWeight: FontWeight.w600,
    );
    final compassEntries = <({String label, double dx, double dy})>[
      (label: 'N', dx: 0.0, dy: -radius - 2.0),
      (label: 'S', dx: 0.0, dy: radius - 12.0),
      (label: 'E', dx: radius - 10.0, dy: -6.0),
      (label: 'W', dx: -radius + 2.0, dy: -6.0),
    ];
    for (final entry in compassEntries) {
      final tp = TextPainter(
        text: TextSpan(text: entry.label, style: compassStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(center.dx + entry.dx - tp.width / 2, center.dy + entry.dy));
    }

    // Own ship triangle at center
    final ownPaint = Paint()..color = AppColors.cyan;
    const triangleSize = 7.0;
    final path = Path()
      ..moveTo(center.dx, center.dy - triangleSize)
      ..lineTo(center.dx - triangleSize * 0.6, center.dy + triangleSize * 0.6)
      ..lineTo(center.dx + triangleSize * 0.6, center.dy + triangleSize * 0.6)
      ..close();
    canvas.drawPath(path, ownPaint);

    // Targets
    for (final target in targets) {
      if (target.relativeDistanceNm == null || target.relativeBearingDeg == null) continue;
      if (target.status == AisTargetStatus.lost) continue;

      final dist = target.relativeDistanceNm!;
      if (dist > rangeNm) continue;

      final bearingRad = (target.relativeBearingDeg! - 90) * math.pi / 180;
      final tx = center.dx + dist * scale * math.cos(bearingRad);
      final ty = center.dy + dist * scale * math.sin(bearingRad);

      // Color by CPA risk
      final Color dotColor;
      if (target.closestPointNm != null && target.closestPointNm! < 0.5) {
        dotColor = AppColors.danger;
      } else if (target.closestPointNm != null && target.closestPointNm! < 1.0) {
        dotColor = AppColors.warning;
      } else {
        dotColor = AppColors.success;
      }

      final dotPaint = Paint()..color = dotColor;
      canvas.drawCircle(Offset(tx, ty), 5, dotPaint);

      // Heading vector (short line)
      if (target.cog != null && target.sog != null && target.sog! > 0.5) {
        final cogRad = (target.cog! - 90) * math.pi / 180;
        final vecLen = target.sog! * scale * 0.5;
        final vecPaint = Paint()
          ..color = dotColor.withOpacity(0.7)
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(
          Offset(tx, ty),
          Offset(tx + vecLen * math.cos(cogRad), ty + vecLen * math.sin(cogRad)),
          vecPaint,
        );
      }

      // Name label
      if (target.name != null || target.mmsi.isNotEmpty) {
        final nameTp = TextPainter(
          text: TextSpan(
            text: target.name ?? target.mmsi.substring(
                math.max(0, target.mmsi.length - 4)),
            style: TextStyle(
              color: dotColor.withOpacity(0.85),
              fontSize: 9,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        nameTp.paint(canvas, Offset(tx + 7, ty - 5));
      }
    }

    // Outer border
    final borderPaint = Paint()
      ..color = Colors.white.withOpacity(0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(center, radius, borderPaint);
  }

  @override
  bool shouldRepaint(_AisRadarPainter old) => old.targets != targets;
}

// ---------------------------------------------------------------------------
// Nearby Tab
// ---------------------------------------------------------------------------

class _NearbyTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aisState = ref.watch(aisProvider);
    final targets = aisState.targets; // already sorted by distance, lost excluded

    if (targets.isEmpty) {
      return const _EmptyState(
        icon: Icons.directions_boat_outlined,
        message: 'No AIS targets detected',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: targets.length,
      separatorBuilder: (_, __) =>
          const Divider(color: AppColors.border, height: 1, indent: 16, endIndent: 16),
      itemBuilder: (context, index) {
        final target = targets[index];
        return _TargetListTile(
          target: target,
          showRiskIndicator: false,
          onTap: () => _showTargetDetailSheet(context, target),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Risk Tab
// ---------------------------------------------------------------------------

class _RiskTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aisState = ref.watch(aisProvider);
    final riskTargets = aisState.riskTargets;

    if (riskTargets.isEmpty) {
      return const _EmptyState(
        icon: Icons.check_circle_outline,
        iconColor: AppColors.success,
        message: 'No collision risks detected',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: riskTargets.length,
      separatorBuilder: (_, __) =>
          const Divider(color: AppColors.border, height: 1, indent: 16, endIndent: 16),
      itemBuilder: (context, index) {
        final target = riskTargets[index];
        return _TargetListTile(
          target: target,
          showRiskIndicator: true,
          onTap: () => _showTargetDetailSheet(context, target),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Own Ship Tab
// ---------------------------------------------------------------------------

class _OwnShipTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aisState = ref.watch(aisProvider);
    final own = aisState.ownShip;

    if (own == null) {
      return const _EmptyState(
        icon: Icons.location_off_outlined,
        message: 'No own ship AIS data',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          decoration: BoxDecoration(
            color: AppColors.cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Row(
                  children: [
                    const Icon(Icons.directions_boat, color: AppColors.cyan, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      own.name ?? own.mmsi ?? 'Own Ship',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Divider(color: AppColors.border, height: 1),
              _OwnShipField('MMSI', own.mmsi ?? '—'),
              _OwnShipField('Name', own.name ?? '—'),
              _OwnShipField('Call Sign', own.callSign ?? '—'),
              _OwnShipField(
                'Ship Type',
                own.shipType != null ? own.shipType.toString() : '—',
              ),
              _OwnShipField(
                'SOG',
                own.sog != null ? '${own.sog!.toStringAsFixed(1)} kn' : '—',
              ),
              _OwnShipField(
                'COG',
                own.cog != null ? '${own.cog!.toStringAsFixed(1)}°' : '—',
              ),
              _OwnShipField(
                'Heading',
                own.heading != null ? '${own.heading!.toStringAsFixed(1)}°' : '—',
              ),
              _OwnShipField('Nav Status', own.navStatus ?? '—'),
              if (own.position != null)
                _OwnShipField(
                  'Position',
                  '${own.position!.latitude.toStringAsFixed(5)}°, '
                  '${own.position!.longitude.toStringAsFixed(5)}°',
                ),
              if (own.lastUpdated != null)
                _OwnShipField(
                  'Last Updated',
                  _formatAge(own.lastUpdated!),
                ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ],
    );
  }

  String _formatAge(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }
}

class _OwnShipField extends StatelessWidget {
  final String label;
  final String value;
  const _OwnShipField(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13)),
          Text(value,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared: Target list tile
// ---------------------------------------------------------------------------

class _TargetListTile extends StatelessWidget {
  final AisTargetState target;
  final bool showRiskIndicator;
  final VoidCallback onTap;

  const _TargetListTile({
    required this.target,
    required this.showRiskIndicator,
    required this.onTap,
  });

  Color get _statusDotColor {
    switch (target.status) {
      case AisTargetStatus.active:
        return AppColors.success;
      case AisTargetStatus.stale:
        return AppColors.warning;
      case AisTargetStatus.lost:
        return AppColors.inactive;
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status dot
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _statusDotColor,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(width: 10),

            // Main content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          target.displayName,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (showRiskIndicator)
                        _RiskBadge(tcpa: target.tcpaMinutes),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 12,
                    runSpacing: 2,
                    children: [
                      if (target.relativeDistanceNm != null)
                        _InfoChip(
                          '${target.relativeDistanceNm!.toStringAsFixed(1)} NM',
                          Icons.straighten,
                        ),
                      if (target.relativeBearingDeg != null)
                        _InfoChip(
                          '${target.relativeBearingDeg!.toStringAsFixed(0)}°',
                          Icons.explore,
                        ),
                      if (target.sog != null)
                        _InfoChip(
                          '${target.sog!.toStringAsFixed(1)} kn',
                          Icons.speed,
                        ),
                      if (target.closestPointNm != null)
                        _InfoChip(
                          'CPA ${target.closestPointNm!.toStringAsFixed(2)} NM',
                          Icons.close_fullscreen,
                          color: _cpaColor(target.closestPointNm!),
                        ),
                      if (target.tcpaMinutes != null)
                        _InfoChip(
                          'TCPA ${target.tcpaMinutes!.toStringAsFixed(0)} min',
                          Icons.timer_outlined,
                          color: _tcpaColor(target.tcpaMinutes!),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: AppColors.textMuted, size: 18),
          ],
        ),
      ),
    );
  }

  Color _cpaColor(double cpa) {
    if (cpa < 0.5) return AppColors.danger;
    if (cpa < 1.0) return AppColors.warning;
    return AppColors.textSecondary;
  }

  Color _tcpaColor(double tcpa) {
    if (tcpa < 10) return AppColors.danger;
    if (tcpa < 20) return AppColors.warning;
    return AppColors.textSecondary;
  }
}

class _InfoChip extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color color;

  const _InfoChip(this.text, this.icon,
      {this.color = AppColors.textSecondary});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 3),
        Text(text, style: TextStyle(color: color, fontSize: 12)),
      ],
    );
  }
}

class _RiskBadge extends StatelessWidget {
  final double? tcpa;
  const _RiskBadge({this.tcpa});

  @override
  Widget build(BuildContext context) {
    final isImmediate = tcpa != null && tcpa! < 10;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: isImmediate
            ? AppColors.danger.withOpacity(0.2)
            : AppColors.warning.withOpacity(0.2),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isImmediate ? AppColors.danger : AppColors.warning,
          width: 0.8,
        ),
      ),
      child: Text(
        isImmediate ? 'HIGH RISK' : 'RISK',
        style: TextStyle(
          color: isImmediate ? AppColors.danger : AppColors.warning,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Target detail bottom sheet
// ---------------------------------------------------------------------------

void _showTargetDetailSheet(BuildContext context, AisTargetState target) {
  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    isScrollControlled: true,
    builder: (_) => _TargetDetailSheet(target: target),
  );
}

class _TargetDetailSheet extends StatelessWidget {
  final AisTargetState target;
  const _TargetDetailSheet({required this.target});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
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
                  const Icon(Icons.directions_boat,
                      color: AppColors.cyan, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      target.displayName,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _StatusPill(target.status),
                ],
              ),
            ),
            const SizedBox(height: 4),
            const Divider(color: AppColors.border, indent: 20, endIndent: 20),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                children: [
                  _DetailRow('MMSI', target.mmsi),
                  if (target.name != null) _DetailRow('Name', target.name!),
                  if (target.callSign != null)
                    _DetailRow('Call Sign', target.callSign!),
                  if (target.shipType != null)
                    _DetailRow('Ship Type', target.shipType.toString()),
                  if (target.navStatus != null)
                    _DetailRow('Nav Status', target.navStatus!),
                  if (target.destination != null)
                    _DetailRow('Destination', target.destination!),
                  if (target.eta != null)
                    _DetailRow('ETA',
                        '${target.eta!.day}/${target.eta!.month} ${target.eta!.hour.toString().padLeft(2, '0')}:${target.eta!.minute.toString().padLeft(2, '0')}'),
                  const Divider(color: AppColors.border, height: 24),
                  if (target.position != null) ...[
                    _DetailRow('Latitude',
                        '${target.position!.latitude.toStringAsFixed(5)}°'),
                    _DetailRow('Longitude',
                        '${target.position!.longitude.toStringAsFixed(5)}°'),
                  ],
                  if (target.sog != null)
                    _DetailRow(
                        'SOG', '${target.sog!.toStringAsFixed(1)} kn'),
                  if (target.cog != null)
                    _DetailRow(
                        'COG', '${target.cog!.toStringAsFixed(1)}°'),
                  if (target.heading != null)
                    _DetailRow(
                        'Heading', '${target.heading!.toStringAsFixed(1)}°'),
                  const Divider(color: AppColors.border, height: 24),
                  if (target.relativeDistanceNm != null)
                    _DetailRow('Distance',
                        '${target.relativeDistanceNm!.toStringAsFixed(2)} NM'),
                  if (target.relativeBearingDeg != null)
                    _DetailRow('Bearing',
                        '${target.relativeBearingDeg!.toStringAsFixed(1)}°'),
                  if (target.closestPointNm != null)
                    _DetailRow('CPA',
                        '${target.closestPointNm!.toStringAsFixed(3)} NM'),
                  if (target.tcpaMinutes != null)
                    _DetailRow('TCPA',
                        '${target.tcpaMinutes!.toStringAsFixed(1)} min'),
                  const Divider(color: AppColors.border, height: 24),
                  _DetailRow('Source',
                      target.signalSource.name.toUpperCase()),
                  _DetailRow('Last Updated', '${target.ageSec}s ago'),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13)),
          Text(value,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final AisTargetStatus status;
  const _StatusPill(this.status);

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;
    switch (status) {
      case AisTargetStatus.active:
        color = AppColors.success;
        label = 'Active';
        break;
      case AisTargetStatus.stale:
        color = AppColors.warning;
        label = 'Stale';
        break;
      case AisTargetStatus.lost:
        color = AppColors.inactive;
        label = 'Lost';
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600)),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state widget
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color iconColor;

  const _EmptyState({
    required this.icon,
    required this.message,
    this.iconColor = AppColors.inactive,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: iconColor),
          const SizedBox(height: 16),
          Text(
            message,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 15),
          ),
        ],
      ),
    );
  }
}
