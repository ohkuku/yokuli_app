import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// A single instrument card showing label + numeric value + optional gauge bar.
class InstrumentCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final Color accentColor;
  final double? gaugeValue; // 0.0 .. 1.0
  final Color? gaugeColor;

  const InstrumentCard({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    this.accentColor = AppColors.cyan,
    this.gaugeValue,
    this.gaugeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 2,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  accentColor.withAlpha(200),
                  accentColor.withAlpha(0),
                ]),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(14)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 14, color: accentColor),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      value,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 28,
                        fontWeight: FontWeight.w300,
                        fontFeatures: [FontFeature.tabularFigures()],
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        unit,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                if (gaugeValue != null) ...[
                  const SizedBox(height: 10),
                  _GaugeBar(
                    value: gaugeValue!.clamp(0.0, 1.0),
                    color: gaugeColor ?? accentColor,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GaugeBar extends StatelessWidget {
  final double value;
  final Color color;

  const _GaugeBar({required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      return Container(
        height: 4,
        width: constraints.maxWidth,
        decoration: BoxDecoration(
          color: AppColors.gaugeTrack,
          borderRadius: BorderRadius.circular(2),
        ),
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: value,
          child: Container(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
              boxShadow: [BoxShadow(color: color.withAlpha(120), blurRadius: 4)],
            ),
          ),
        ),
      );
    });
  }
}

/// Compass card with heading (cyan) and COG (green) arrows
class CompassCard extends StatelessWidget {
  final double? headingDeg;
  final double? cogDeg;

  const CompassCard({super.key, this.headingDeg, this.cogDeg});

  @override
  Widget build(BuildContext context) {
    final display = headingDeg ?? cogDeg;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.explore_rounded, size: 14, color: AppColors.cyan),
                const SizedBox(width: 6),
                const Text(
                  'HEADING / COG',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.0,
                  ),
                ),
                const Spacer(),
                if (cogDeg != null)
                  Row(children: [
                    Container(width: 8, height: 2, color: AppColors.success),
                    const SizedBox(width: 4),
                    const Text('COG',
                        style: TextStyle(
                            color: AppColors.textMuted, fontSize: 9)),
                  ]),
              ],
            ),
            Expanded(
              child: CustomPaint(
                painter: _CompassPainter(
                    headingDeg: headingDeg, cogDeg: cogDeg),
                child: Container(),
              ),
            ),
            Text(
              display != null ? '${display.toStringAsFixed(0)}°T' : '— °T',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w300,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompassPainter extends CustomPainter {
  final double? headingDeg;
  final double? cogDeg;

  _CompassPainter({this.headingDeg, this.cogDeg});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = (size.shortestSide / 2) * 0.85;

    // Outer ring
    canvas.drawCircle(
      Offset(cx, cy),
      radius,
      Paint()
        ..color = AppColors.border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Tick marks every 10° (major every 90°)
    for (int i = 0; i < 36; i++) {
      final deg = i * 10.0;
      final rad = (deg - 90) * math.pi / 180;
      final isMajor = i % 9 == 0;
      final inner = radius * (isMajor ? 0.80 : 0.90);
      canvas.drawLine(
        Offset(cx + inner * math.cos(rad), cy + inner * math.sin(rad)),
        Offset(cx + radius * math.cos(rad), cy + radius * math.sin(rad)),
        Paint()
          ..color = isMajor ? AppColors.textSecondary : AppColors.textDim
          ..strokeWidth = isMajor ? 1.5 : 0.8,
      );
    }

    // Cardinal labels N/E/S/W
    const cardinals = ['N', 'E', 'S', 'W'];
    for (int i = 0; i < 4; i++) {
      final rad = (i * 90.0 - 90) * math.pi / 180;
      final labelR = radius * 0.68;
      final tp = TextPainter(
        text: TextSpan(
          text: cardinals[i],
          style: TextStyle(
            color: i == 0 ? AppColors.danger : AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(cx + labelR * math.cos(rad) - tp.width / 2,
            cy + labelR * math.sin(rad) - tp.height / 2),
      );
    }

    // COG arrow (green)
    if (cogDeg != null) {
      _drawArrow(canvas, cx, cy, radius * 0.72, cogDeg!, AppColors.success, 2.0);
    }

    // Heading arrow (cyan, slightly shorter)
    if (headingDeg != null) {
      _drawArrow(canvas, cx, cy, radius * 0.62, headingDeg!, AppColors.cyan, 3.0);
    }
  }

  void _drawArrow(Canvas canvas, double cx, double cy, double length,
      double deg, Color color, double sw) {
    final rad = (deg - 90) * math.pi / 180;
    final tx = cx + length * math.cos(rad);
    final ty = cy + length * math.sin(rad);
    final bx = cx - length * 0.25 * math.cos(rad);
    final by = cy - length * 0.25 * math.sin(rad);

    final paint = Paint()
      ..color = color
      ..strokeWidth = sw
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(Offset(bx, by), Offset(tx, ty), paint);

    // Arrowhead
    final hs = length * 0.18;
    for (final side in [-0.45, 0.45]) {
      canvas.drawLine(
        Offset(tx, ty),
        Offset(tx - hs * math.cos(rad + side),
            ty - hs * math.sin(rad + side)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_CompassPainter old) =>
      old.headingDeg != headingDeg || old.cogDeg != cogDeg;
}

/// Wind angle display (apparent wind)
class WindAngleCard extends StatelessWidget {
  final double? apparentWindAngle; // -180..+180, neg=port
  final double? apparentWindSpeed;
  final double? trueWindSpeed;

  const WindAngleCard({
    super.key,
    this.apparentWindAngle,
    this.apparentWindSpeed,
    this.trueWindSpeed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.air_rounded, size: 14, color: AppColors.teal),
              const SizedBox(width: 6),
              const Text('WIND',
                  style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.0)),
            ]),
            Expanded(
              child: CustomPaint(
                painter: _WindPainter(angle: apparentWindAngle),
                child: Container(),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('AWA',
                      style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 9,
                          letterSpacing: 0.8)),
                  Text(
                    apparentWindAngle != null
                        ? '${apparentWindAngle!.toStringAsFixed(0)}°'
                        : '—',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ]),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  const Text('AWS',
                      style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 9,
                          letterSpacing: 0.8)),
                  Text(
                    apparentWindSpeed != null
                        ? '${apparentWindSpeed!.toStringAsFixed(1)} kn'
                        : '—',
                    style: const TextStyle(
                      color: AppColors.teal,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ]),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WindPainter extends CustomPainter {
  final double? angle; // degrees, neg=port

  _WindPainter({this.angle});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = (size.shortestSide / 2) * 0.80;

    // Half-circle arc (bow up)
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      math.pi,
      math.pi,
      false,
      Paint()
        ..color = AppColors.border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Center boat indicator
    canvas.drawLine(
      Offset(cx, cy - r * 0.2),
      Offset(cx, cy + r * 0.2),
      Paint()
        ..color = AppColors.textDim
        ..strokeWidth = 2,
    );

    if (angle == null) return;

    // Wind arrow — angle 0=bow, +starboard, -port
    final rad = (angle! - 90) * math.pi / 180; // offset so 0=top
    final length = r * 0.75;
    final tx = cx + length * math.cos(rad);
    final ty = cy + length * math.sin(rad);

    final paint = Paint()
      ..color = AppColors.teal
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(Offset(cx, cy), Offset(tx, ty), paint);
    final hs = length * 0.22;
    for (final s in [-0.4, 0.4]) {
      canvas.drawLine(
        Offset(tx, ty),
        Offset(tx - hs * math.cos(rad + s), ty - hs * math.sin(rad + s)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WindPainter old) => old.angle != angle;
}
