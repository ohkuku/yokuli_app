import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import '../../../core/theme/app_colors.dart';
import '../../../core/providers/ais_provider.dart';
import '../../../core/providers/vessel_provider.dart';
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
              Tab(text: '雷达'),
              Tab(text: '附近'),
              Tab(text: '碰撞风险'),
              Tab(text: '本船'),
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
// Radar Tab — map view (with polar-chart fallback)
// ---------------------------------------------------------------------------

enum _RadarMode { northUp, headingUp }

class _RadarTab extends ConsumerStatefulWidget {
  @override
  ConsumerState<_RadarTab> createState() => _RadarTabState();
}

class _RadarTabState extends ConsumerState<_RadarTab> {
  bool _showMap = true;
  final _mapController = MapController();
  _RadarMode _mode = _RadarMode.northUp;
  _RadarMode _mapMode = _RadarMode.northUp; // separate mode for map view
  double _rangeNm = 0; // 0 = auto

  static const _zoomSteps = [0.5, 1.0, 2.0, 5.0, 10.0, 20.0];

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  void _zoomIn() {
    if (_rangeNm == 0) return;
    final idx = _zoomSteps.indexWhere((s) => s >= _rangeNm);
    if (idx > 0) setState(() => _rangeNm = _zoomSteps[idx - 1]);
  }

  void _zoomOut() {
    if (_rangeNm == 0) {
      setState(() => _rangeNm = _zoomSteps[1]);
      return;
    }
    final idx = _zoomSteps.lastIndexWhere((s) => s <= _rangeNm);
    if (idx < _zoomSteps.length - 1) setState(() => _rangeNm = _zoomSteps[idx + 1]);
  }

  void _onRadarTap(BuildContext context, Offset tap, Size size) {
    final minDim = math.min(size.width, size.height);
    final center = Offset(size.width / 2, size.height / 2);
    final radius = minDim / 2 - 8;

    var dx = tap.dx - center.dx;
    var dy = tap.dy - center.dy;

    // Reverse heading-up rotation
    if (_mode == _RadarMode.headingUp) {
      final vessel = ref.read(vesselProvider);
      final hdg = vessel.heading;
      if (hdg != null) {
        final rot = hdg * math.pi / 180.0;
        final ndx = dx * math.cos(rot) - dy * math.sin(rot);
        final ndy = dx * math.sin(rot) + dy * math.cos(rot);
        dx = ndx;
        dy = ndy;
      }
    }

    // Compute effective range for scale
    double maxDist = 3.0;
    final targets = ref.read(aisProvider).targets
        .where((t) => t.status != AisTargetStatus.lost)
        .toList();
    for (final t in targets) {
      if (t.relativeDistanceNm != null && t.relativeDistanceNm! > maxDist) {
        maxDist = math.min(t.relativeDistanceNm!, 20.0);
      }
    }
    final effectiveRange = _rangeNm > 0
        ? _rangeNm
        : (maxDist <= 3
            ? 3.0
            : maxDist <= 6
                ? 6.0
                : maxDist <= 10
                    ? 10.0
                    : 20.0);
    final scale = radius / effectiveRange;

    // Collect all targets within 36px tap radius
    const tapRadiusPx2 = 36.0 * 36.0;
    final hits = <AisTargetState>[];

    for (final t in targets) {
      if (t.relativeBearingDeg == null || t.relativeDistanceNm == null) continue;
      if (t.relativeDistanceNm! > effectiveRange) continue;
      final bearRad = (t.relativeBearingDeg! - 90) * math.pi / 180;
      final tx = t.relativeDistanceNm! * scale * math.cos(bearRad);
      final ty = t.relativeDistanceNm! * scale * math.sin(bearRad);
      final d2 = (dx - tx) * (dx - tx) + (dy - ty) * (dy - ty);
      if (d2 <= tapRadiusPx2) hits.add(t);
    }

    if (hits.isEmpty) return;
    if (hits.length == 1) {
      _showTargetDetailSheet(context, hits.first);
    } else {
      // Sort by distance, then show picker
      hits.sort((a, b) =>
          (a.relativeDistanceNm ?? 99).compareTo(b.relativeDistanceNm ?? 99));
      _showTargetPickerSheet(context, hits);
    }
  }

  void _showTargetPickerSheet(BuildContext context, List<AisTargetState> hits) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _TargetPickerSheet(
        targets: hits,
        onSelect: (t) {
          Navigator.of(context).pop();
          _showTargetDetailSheet(context, t);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final targets = ref.watch(aisProvider).targets.where(
          (t) => t.status != AisTargetStatus.lost,
        ).toList();
    final ownPos = ref.watch(vesselProvider).position;

    if (_showMap && ownPos != null) {
      return _buildMapView(ownPos, targets);
    }
    return _buildPolarView(targets, ownPos != null);
  }

  Widget _buildMapView(dynamic ownPos, List<AisTargetState> targets) {
    final center = ll.LatLng(ownPos.latitude as double, ownPos.longitude as double);
    final vessel = ref.watch(vesselProvider);
    final hdg = vessel.heading;

    // Apply heading-up rotation
    if (_mapMode == _RadarMode.headingUp && hdg != null) {
      try { _mapController.rotate(-hdg); } catch (_) {}
    } else if (_mapMode == _RadarMode.northUp) {
      try { _mapController.rotate(0); } catch (_) {}
    }

    final markers = <Marker>[
      // Own ship
      Marker(
        point: center,
        width: 28,
        height: 28,
        child: Transform.rotate(
          angle: (_mapMode == _RadarMode.headingUp ? 0 : (hdg ?? 0)) *
              math.pi / 180.0,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.cyan,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: const Icon(Icons.navigation_rounded,
                color: Colors.white, size: 14),
          ),
        ),
      ),
      // AIS targets
      for (final t in targets)
        if (t.position != null)
          Marker(
            point: ll.LatLng(t.position!.latitude, t.position!.longitude),
            width: 80,
            height: 44,
            child: GestureDetector(
              onTap: () => _showTargetDetailSheet(context, t),
              child: _AisMapMarker(target: t),
            ),
          ),
    ];

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: 12,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.yokuli.app',
            ),
            MarkerLayer(markers: markers),
          ],
        ),
        // Top-left: heading mode toggle
        Positioned(
          top: 8,
          left: 8,
          child: _RadarModeToggle(
            mode: _mapMode,
            onChanged: (m) => setState(() => _mapMode = m),
          ),
        ),
        // Top-right: switch to polar radar
        Positioned(
          top: 8,
          right: 8,
          child: _MapIconBtn(
            icon: Icons.radar_rounded,
            tooltip: 'Polar radar',
            onTap: () => setState(() => _showMap = false),
          ),
        ),
        // Bottom-right: re-center
        Positioned(
          bottom: 16,
          right: 8,
          child: _MapIconBtn(
            icon: Icons.my_location_rounded,
            tooltip: 'Center',
            onTap: () {
              try {
                _mapController.move(center, _mapController.camera.zoom);
              } catch (_) {}
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPolarView(List<AisTargetState> targets, bool hasPosition) {
    final vessel = ref.watch(vesselProvider);
    final headingDeg = vessel.heading;
    final cogDeg = vessel.courseOverGround;
    final sog = vessel.speedOverGround;

    return Column(
      children: [
        // Top controls row
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              // Map button (when has position)
              if (hasPosition) ...[
                _MapIconBtn(
                  icon: Icons.map_rounded,
                  label: 'Map',
                  onTap: () => setState(() => _showMap = true),
                ),
                const SizedBox(width: 8),
              ],
              // Mode toggle
              _RadarModeToggle(
                  mode: _mode, onChanged: (m) => setState(() => _mode = m)),
              const Spacer(),
              // Range display
              Text(
                _rangeNm > 0
                    ? '${_rangeNm % 1 == 0 ? _rangeNm.toInt() : _rangeNm} NM'
                    : 'AUTO',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(width: 8),
              // Zoom buttons
              _RadarBtn(icon: Icons.remove, onTap: _zoomOut),
              const SizedBox(width: 4),
              _RadarBtn(icon: Icons.add, onTap: _zoomIn),
            ],
          ),
        ),
        // Radar circle
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
            child: AspectRatio(
              aspectRatio: 1,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = constraints.biggest;
                  return GestureDetector(
                    onTapUp: (details) =>
                        _onRadarTap(context, details.localPosition, size),
                    child: CustomPaint(
                      size: size,
                      painter: _AisRadarPainter(
                        targets: targets,
                        mode: _mode,
                        rangeNm: _rangeNm,
                        ownHeadingDeg: headingDeg,
                        ownCogDeg: cogDeg,
                        ownSog: sog,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        // Legend
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _LegendDot(color: AppColors.danger, label: 'High Risk (<0.5NM)'),
              const SizedBox(width: 12),
              _LegendDot(color: AppColors.warning, label: 'Caution'),
              const SizedBox(width: 12),
              _LegendDot(color: AppColors.success, label: 'Clear'),
            ],
          ),
        ),
      ],
    );
  }
}

class _MapIconBtn extends StatelessWidget {
  final IconData icon;
  final String? label;
  final String? tooltip;
  final VoidCallback onTap;

  const _MapIconBtn({required this.icon, required this.onTap, this.label, this.tooltip});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: label != null ? 10 : 8, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surface.withOpacity(0.92),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppColors.cyan),
            if (label != null) ...[
              const SizedBox(width: 4),
              Text(label!, style: const TextStyle(color: AppColors.cyan, fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }
}

class _AisMapMarker extends StatelessWidget {
  final AisTargetState target;
  const _AisMapMarker({required this.target});

  Color _color() {
    if (target.closestPointNm != null && target.closestPointNm! < 0.5) {
      return AppColors.danger;
    } else if (target.closestPointNm != null && target.closestPointNm! < 1.0) {
      return AppColors.warning;
    }
    return AppColors.success;
  }

  @override
  Widget build(BuildContext context) {
    final color = _color();
    final label = target.name ??
        (target.mmsi.length >= 4
            ? target.mmsi.substring(target.mmsi.length - 4)
            : target.mmsi);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white70, width: 1),
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            shadows: const [Shadow(color: Colors.black, blurRadius: 3)],
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
  final _RadarMode mode;
  final double rangeNm; // 0 = auto
  final double? ownHeadingDeg;
  final double? ownCogDeg;
  final double? ownSog;

  const _AisRadarPainter({
    required this.targets,
    required this.mode,
    required this.rangeNm,
    this.ownHeadingDeg,
    this.ownCogDeg,
    this.ownSog,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 8;

    // Determine effective range
    double maxDist = 3.0;
    for (final t in targets) {
      if (t.relativeDistanceNm != null && t.relativeDistanceNm! > maxDist) {
        maxDist = math.min(t.relativeDistanceNm!, 20.0);
      }
    }
    final effectiveRange = rangeNm > 0
        ? rangeNm
        : (maxDist <= 3
            ? 3.0
            : maxDist <= 6
                ? 6.0
                : maxDist <= 10
                    ? 10.0
                    : 20.0);
    final scale = radius / effectiveRange;

    // --- Rotated context for heading-up mode ---
    canvas.save();
    canvas.translate(center.dx, center.dy);
    if (mode == _RadarMode.headingUp && ownHeadingDeg != null) {
      canvas.rotate(-ownHeadingDeg! * math.pi / 180.0);
    }
    canvas.translate(-center.dx, -center.dy);

    // Background
    final bgPaint = Paint()..color = const Color(0xFF0A1A2F);
    canvas.drawCircle(center, radius, bgPaint);

    // Range rings
    final ringPaint = Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    final ringIntervals = effectiveRange <= 3
        ? [1.0, 2.0, 3.0]
        : effectiveRange <= 6
            ? [2.0, 4.0, 6.0]
            : effectiveRange <= 10
                ? [2.5, 5.0, 10.0]
                : [5.0, 10.0, 20.0];

    final labelStyle = TextStyle(
      color: Colors.white.withOpacity(0.3),
      fontSize: 9,
    );

    for (final nm in ringIntervals) {
      final r = nm * scale;
      canvas.drawCircle(center, r, ringPaint);
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
      tp.paint(canvas,
          Offset(center.dx + entry.dx - tp.width / 2, center.dy + entry.dy));
    }

    // Own COG vector (inside rotated context)
    if (ownCogDeg != null && ownSog != null && ownSog! > 0.3) {
      final cogRad = (ownCogDeg! - 90) * math.pi / 180;
      final vecNm = ownSog! * 6.0 / 60.0; // 6 minute predictor
      final vecPx = vecNm * scale;
      final vecPaint = Paint()
        ..color = AppColors.cyan.withOpacity(0.6)
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        center,
        Offset(center.dx + vecPx * math.cos(cogRad),
            center.dy + vecPx * math.sin(cogRad)),
        vecPaint,
      );
    }

    // Targets (inside rotated context)
    for (final target in targets) {
      if (target.relativeDistanceNm == null ||
          target.relativeBearingDeg == null) continue;
      if (target.status == AisTargetStatus.lost) continue;

      final dist = target.relativeDistanceNm!;
      if (dist > effectiveRange) continue;

      final bearingRad = (target.relativeBearingDeg! - 90) * math.pi / 180;
      final tx = center.dx + dist * scale * math.cos(bearingRad);
      final ty = center.dy + dist * scale * math.sin(bearingRad);

      final Color dotColor;
      if (target.closestPointNm != null && target.closestPointNm! < 0.5) {
        dotColor = AppColors.danger;
      } else if (target.closestPointNm != null &&
          target.closestPointNm! < 1.0) {
        dotColor = AppColors.warning;
      } else {
        dotColor = AppColors.success;
      }

      final dotPaint = Paint()..color = dotColor;
      canvas.drawCircle(Offset(tx, ty), 5, dotPaint);

      if (target.cog != null && target.sog != null && target.sog! > 0.5) {
        final cogRad = (target.cog! - 90) * math.pi / 180;
        final vecLen = target.sog! * scale * 0.5;
        final vecPaint = Paint()
          ..color = dotColor.withOpacity(0.7)
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(
          Offset(tx, ty),
          Offset(tx + vecLen * math.cos(cogRad),
              ty + vecLen * math.sin(cogRad)),
          vecPaint,
        );
      }

      if (target.name != null || target.mmsi.isNotEmpty) {
        final nameTp = TextPainter(
          text: TextSpan(
            text: target.name ??
                target.mmsi
                    .substring(math.max(0, target.mmsi.length - 4)),
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

    canvas.restore();
    // --- End rotated context ---

    // Own ship triangle (always screen-upright after restore)
    canvas.save();
    canvas.translate(center.dx, center.dy);
    if (mode == _RadarMode.northUp && ownHeadingDeg != null) {
      canvas.rotate(ownHeadingDeg! * math.pi / 180.0);
    }
    // In heading-up mode the canvas was already rotated so triangle points toward heading (up)
    final triPath = Path()
      ..moveTo(0, -7.0)
      ..lineTo(-4.2, 4.2)
      ..lineTo(4.2, 4.2)
      ..close();
    canvas.drawPath(triPath, Paint()..color = AppColors.cyan);
    canvas.restore();

    // North indicator for heading-up mode
    if (mode == _RadarMode.headingUp && ownHeadingDeg != null) {
      final northRad = ownHeadingDeg! * math.pi / 180.0;
      final northDx = math.sin(northRad);
      final northDy = -math.cos(northRad);
      final arrowTip = Offset(
        center.dx + northDx * (radius - 14),
        center.dy + northDy * (radius - 14),
      );
      final arrowBase = Offset(
        center.dx + northDx * (radius - 22),
        center.dy + northDy * (radius - 22),
      );
      final northPaint = Paint()
        ..color = Colors.white.withOpacity(0.6)
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(arrowBase, arrowTip, northPaint);
      final nTp = TextPainter(
        text: TextSpan(
          text: 'N',
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 9,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      nTp.paint(
        canvas,
        Offset(arrowTip.dx - nTp.width / 2, arrowTip.dy - nTp.height / 2),
      );
    }

    // Outer border
    final borderPaint = Paint()
      ..color = Colors.white.withOpacity(0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(center, radius, borderPaint);
  }

  @override
  bool shouldRepaint(_AisRadarPainter old) =>
      old.targets != targets ||
      old.mode != mode ||
      old.rangeNm != rangeNm ||
      old.ownHeadingDeg != ownHeadingDeg ||
      old.ownCogDeg != ownCogDeg ||
      old.ownSog != ownSog;
}

// ---------------------------------------------------------------------------
// Radar helper widgets
// ---------------------------------------------------------------------------

class _RadarModeToggle extends StatelessWidget {
  final _RadarMode mode;
  final ValueChanged<_RadarMode> onChanged;
  const _RadarModeToggle({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ModeBtn(
            label: 'N-UP',
            selected: mode == _RadarMode.northUp,
            onTap: () => onChanged(_RadarMode.northUp),
          ),
          Container(width: 1, height: 28, color: AppColors.border),
          _ModeBtn(
            label: 'HDG-UP',
            selected: mode == _RadarMode.headingUp,
            onTap: () => onChanged(_RadarMode.headingUp),
          ),
        ],
      ),
    );
  }
}

class _ModeBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ModeBtn(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color:
                selected ? AppColors.cyan.withAlpha(30) : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? AppColors.cyan : AppColors.textMuted,
              fontSize: 11,
              fontWeight:
                  selected ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
      );
}

class _RadarBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _RadarBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.border),
          ),
          child: Icon(icon, size: 14, color: AppColors.cyan),
        ),
      );
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
    final vessel = ref.watch(vesselProvider);
    final own = aisState.ownShip;

    // Use AIS own-ship data if available; fall back to vessel navigation data.
    final String title = own?.name ?? own?.mmsi ?? '本船';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Info banner when no AIS transponder data
        if (own == null)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.warning.withAlpha(18),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.warning.withAlpha(80)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    color: AppColors.warning, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '未检测到本船 AIS 应答器数据，显示导航传感器数据',
                    style:
                        TextStyle(color: AppColors.warning, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),

        // Main data card
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
                    const Icon(Icons.directions_boat,
                        color: AppColors.cyan, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (own?.lastUpdated != null)
                      Text(
                        _formatAge(own!.lastUpdated!),
                        style: const TextStyle(
                            color: AppColors.textMuted, fontSize: 11),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Divider(color: AppColors.border, height: 1),

              // AIS-specific fields (only when transponder data available)
              if (own != null) ...[
                _OwnShipField('MMSI', own.mmsi ?? '—'),
                _OwnShipField('船名', own.name ?? '—'),
                _OwnShipField('呼号', own.callSign ?? '—'),
                _OwnShipField(
                  '船型',
                  own.shipType != null ? own.shipType.toString() : '—',
                ),
                _OwnShipField('航行状态', own.navStatus ?? '—'),
              ],

              // Navigation fields: prefer AIS, fall back to vessel sensors
              _OwnShipField(
                '航速 (SOG)',
                _fmt1(own?.sog ?? vessel.speedOverGround, 'kn'),
              ),
              _OwnShipField(
                '航向 (COG)',
                _fmtDeg(own?.cog ?? vessel.courseOverGround),
              ),
              _OwnShipField(
                '船首向 (HDG)',
                _fmtDeg(own?.heading ?? vessel.heading),
              ),
              _OwnShipField(
                '位置',
                _fmtPosition(
                  own?.position ?? vessel.position,
                ),
              ),
              if (vessel.depthBelowKeel != null)
                _OwnShipField(
                  '龙骨水深',
                  '${vessel.depthBelowKeel!.toStringAsFixed(1)} m',
                ),
              if (vessel.trueWindSpeed != null)
                _OwnShipField(
                  '真风速',
                  '${vessel.trueWindSpeed!.toStringAsFixed(1)} kn',
                ),

              const SizedBox(height: 4),
            ],
          ),
        ),
      ],
    );
  }

  String _fmt1(double? v, String unit) =>
      v != null ? '${v.toStringAsFixed(1)} $unit' : '—';

  String _fmtDeg(double? v) =>
      v != null ? '${v.toStringAsFixed(1)}°' : '—';

  String _fmtPosition(dynamic pos) {
    if (pos == null) return '—';
    try {
      final lat = (pos as dynamic).latitude as double;
      final lon = pos.longitude as double;
      return '${lat.toStringAsFixed(5)}°, ${lon.toStringAsFixed(5)}°';
    } catch (_) {
      return '—';
    }
  }

  String _formatAge(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s 前';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m 前';
    return '${diff.inHours}h 前';
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

// ---------------------------------------------------------------------------
// Target picker sheet (multiple hits at same tap position)
// ---------------------------------------------------------------------------

class _TargetPickerSheet extends StatelessWidget {
  final List<AisTargetState> targets;
  final ValueChanged<AisTargetState> onSelect;
  const _TargetPickerSheet({required this.targets, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.45,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (_, scrollController) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.inactive,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Text(
              '附近船舶',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700),
            ),
          ),
          const Divider(color: AppColors.border, height: 1),
          Expanded(
            child: ListView.separated(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              itemCount: targets.length,
              separatorBuilder: (_, __) =>
                  const Divider(color: AppColors.border, height: 1),
              itemBuilder: (_, i) {
                final t = targets[i];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.directions_boat_rounded,
                      color: AppColors.cyan, size: 20),
                  title: Text(
                    t.displayName,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600),
                  ),
                  subtitle: t.relativeDistanceNm != null
                      ? Text(
                          '${t.relativeDistanceNm!.toStringAsFixed(2)} NM',
                          style: const TextStyle(
                              color: AppColors.textMuted, fontSize: 12),
                        )
                      : null,
                  onTap: () => onSelect(t),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

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

class _TargetDetailSheet extends StatefulWidget {
  final AisTargetState target;
  const _TargetDetailSheet({required this.target});

  @override
  State<_TargetDetailSheet> createState() => _TargetDetailSheetState();
}

class _TargetDetailSheetState extends State<_TargetDetailSheet> {
  // Extra data fetched from public vessel registry
  String? _apiVesselName;
  String? _apiVesselType;
  String? _apiFlag;
  bool _fetching = true;

  @override
  void initState() {
    super.initState();
    _fetchVesselInfo();
  }

  Future<void> _fetchVesselInfo() async {
    try {
      // VT Explorer public API (DEMO key — returns basic vessel info)
      final uri = Uri.parse(
        'https://api.vtexplorer.com/vessels'
        '?userkey=DEMO&mmsi=${widget.target.mmsi}&format=json',
      );
      final resp = await http
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body);
        final list = body is List ? body : (body['vessels'] as List? ?? []);
        if (list.isNotEmpty) {
          final v = list[0] as Map<String, dynamic>;
          if (mounted) {
            setState(() {
              _apiVesselName = v['AIS']?['NAME'] as String? ??
                  v['NAME'] as String?;
              _apiVesselType = v['AIS']?['SHIPTYPE'] as String? ??
                  v['SHIPTYPE'] as String?;
              _apiFlag = v['AIS']?['COUNTRY'] as String? ??
                  v['COUNTRY'] as String?;
            });
          }
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _fetching = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.target;
    // Name: API result > AIS name > MMSI
    final displayName = _apiVesselName?.isNotEmpty == true
        ? _apiVesselName!
        : t.name ?? t.mmsi;

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.95,
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                            child: Text(
                              displayName,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (_fetching)
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: AppColors.textMuted,
                              ),
                            ),
                        ]),
                        if (_apiFlag != null)
                          Text(_apiFlag!,
                              style: const TextStyle(
                                  color: AppColors.textMuted, fontSize: 12)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusPill(t.status),
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
                  // Name is already in header; show AIS name if different from API
                  if (t.name != null &&
                      _apiVesselName != null &&
                      t.name != _apiVesselName)
                    _DetailRow('AIS 船名', t.name!),
                  _DetailRow('MMSI', t.mmsi),
                  if (t.callSign != null) _DetailRow('Call Sign', t.callSign!),
                  if (_apiVesselType != null)
                    _DetailRow('Ship Type', _apiVesselType!)
                  else if (t.shipType != null)
                    _DetailRow('Ship Type', t.shipType.toString()),
                  if (t.navStatus != null)
                    _DetailRow('Nav Status', t.navStatus!),
                  if (t.destination != null)
                    _DetailRow('Destination', t.destination!),
                  if (t.eta != null)
                    _DetailRow('ETA',
                        '${t.eta!.day}/${t.eta!.month} '
                        '${t.eta!.hour.toString().padLeft(2, '0')}:'
                        '${t.eta!.minute.toString().padLeft(2, '0')}'),
                  const Divider(color: AppColors.border, height: 24),
                  if (t.position != null) ...[
                    _DetailRow('Latitude',
                        '${t.position!.latitude.toStringAsFixed(5)}°'),
                    _DetailRow('Longitude',
                        '${t.position!.longitude.toStringAsFixed(5)}°'),
                  ],
                  if (t.sog != null)
                    _DetailRow('SOG', '${t.sog!.toStringAsFixed(1)} kn'),
                  if (t.cog != null)
                    _DetailRow('COG', '${t.cog!.toStringAsFixed(1)}°'),
                  if (t.heading != null)
                    _DetailRow('Heading', '${t.heading!.toStringAsFixed(1)}°'),
                  const Divider(color: AppColors.border, height: 24),
                  if (t.relativeDistanceNm != null)
                    _DetailRow('Distance',
                        '${t.relativeDistanceNm!.toStringAsFixed(2)} NM'),
                  if (t.relativeBearingDeg != null)
                    _DetailRow('Bearing',
                        '${t.relativeBearingDeg!.toStringAsFixed(1)}°'),
                  if (t.closestPointNm != null)
                    _DetailRow('CPA',
                        '${t.closestPointNm!.toStringAsFixed(3)} NM'),
                  if (t.tcpaMinutes != null)
                    _DetailRow('TCPA',
                        '${t.tcpaMinutes!.toStringAsFixed(1)} min'),
                  const Divider(color: AppColors.border, height: 24),
                  _DetailRow('Source', t.signalSource.name.toUpperCase()),
                  _DetailRow('Last Updated', '${t.ageSec}s ago'),
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
