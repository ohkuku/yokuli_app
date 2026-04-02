import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Bottom-sheet helper
// ─────────────────────────────────────────────────────────────────────────────

void showInstrumentDetail(
  BuildContext context, {
  required String title,
  required Widget content,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (ctx, controller) => Column(
        children: [
          // drag handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 8),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.all(20),
              children: [content],
            ),
          ),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// SparklineChart
// ─────────────────────────────────────────────────────────────────────────────

/// A simple sparkline (line + gradient fill) using CustomPainter.
/// Handles empty / single-point lists gracefully.
class SparklineChart extends StatelessWidget {
  final List<double> values;
  final Color color;
  final double? minY;
  final double? maxY;
  final String? unit;
  final double height;

  const SparklineChart({
    super.key,
    required this.values,
    this.color = AppColors.cyan,
    this.minY,
    this.maxY,
    this.unit,
    this.height = 60,
  });

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(
          child: Text(
            '— no history —',
            style: TextStyle(color: AppColors.textMuted, fontSize: 11),
          ),
        ),
      );
    }
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _SparklinePainter(
          values: values,
          color: color,
          minY: minY,
          maxY: maxY,
        ),
        child: Container(),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final Color color;
  final double? minY;
  final double? maxY;

  _SparklinePainter({
    required this.values,
    required this.color,
    this.minY,
    this.maxY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final lo = minY ?? values.reduce(math.min);
    final hi = maxY ?? values.reduce(math.max);
    final range = (hi - lo).abs();
    final effectiveRange = range < 0.001 ? 1.0 : range;

    double xOf(int i) => i * size.width / (values.length - 1).clamp(1, 9999);
    double yOf(double v) =>
        size.height - ((v - lo) / effectiveRange * size.height).clamp(0, size.height);

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withAlpha(60), color.withAlpha(0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    final linePath = Path();
    final fillPath = Path();

    fillPath.moveTo(xOf(0), size.height);

    for (int i = 0; i < values.length; i++) {
      final x = xOf(i);
      final y = yOf(values[i]);
      if (i == 0) {
        linePath.moveTo(x, y);
        fillPath.lineTo(x, y);
      } else {
        linePath.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    fillPath.lineTo(xOf(values.length - 1), size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(linePath, linePaint);

    // Latest value dot
    final lastX = xOf(values.length - 1);
    final lastY = yOf(values.last);
    canvas.drawCircle(
      Offset(lastX, lastY),
      3,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.values != values || old.color != color;
}

// ─────────────────────────────────────────────────────────────────────────────
// InstrumentCard
// ─────────────────────────────────────────────────────────────────────────────

/// A single instrument card showing label + numeric value + optional gauge bar.
class InstrumentCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final Color accentColor;
  final double? gaugeValue; // 0.0 .. 1.0
  final Color? gaugeColor;
  final VoidCallback? onTap;

  const InstrumentCard({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    this.accentColor = AppColors.cyan,
    this.gaugeValue,
    this.gaugeColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Stack(
        children: [
          // Accent top bar
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
                    Expanded(
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.0,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (onTap != null)
                      Icon(
                        Icons.expand_more_rounded,
                        size: 14,
                        color: AppColors.textDim,
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

    if (onTap == null) return card;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        splashColor: accentColor.withAlpha(30),
        highlightColor: accentColor.withAlpha(15),
        child: card,
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

// ─────────────────────────────────────────────────────────────────────────────
// CompassCard
// ─────────────────────────────────────────────────────────────────────────────

/// Compass card with heading (cyan) and COG (green) arrows
class CompassCard extends StatelessWidget {
  final double? headingDeg;
  final double? cogDeg;
  final VoidCallback? onTap;

  const CompassCard({super.key, this.headingDeg, this.cogDeg, this.onTap});

  @override
  Widget build(BuildContext context) {
    final display = headingDeg ?? cogDeg;
    final card = Container(
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
                const Expanded(
                  child: Text(
                    'HEADING / COG',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.0,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (cogDeg != null)
                  Row(children: [
                    Container(width: 8, height: 2, color: AppColors.success),
                    const SizedBox(width: 4),
                    const Text('COG',
                        style: TextStyle(
                            color: AppColors.textMuted, fontSize: 9)),
                  ]),
                if (onTap != null) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.expand_more_rounded,
                      size: 14, color: AppColors.textDim),
                ],
              ],
            ),
            Expanded(
              child: CustomPaint(
                painter: CompassPainter(
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

    if (onTap == null) return card;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        splashColor: AppColors.cyan.withAlpha(30),
        highlightColor: AppColors.cyan.withAlpha(15),
        child: card,
      ),
    );
  }
}

/// Made public so dashboard can reuse a larger version in the detail sheet.
class CompassPainter extends CustomPainter {
  final double? headingDeg;
  final double? cogDeg;

  CompassPainter({this.headingDeg, this.cogDeg});

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
  bool shouldRepaint(CompassPainter old) =>
      old.headingDeg != headingDeg || old.cogDeg != cogDeg;
}

// ─────────────────────────────────────────────────────────────────────────────
// WindAngleCard
// ─────────────────────────────────────────────────────────────────────────────

/// Wind angle display (apparent wind)
class WindAngleCard extends StatelessWidget {
  final double? apparentWindAngle; // -180..+180, neg=port
  final double? apparentWindSpeed;
  final double? trueWindSpeed;
  final VoidCallback? onTap;

  const WindAngleCard({
    super.key,
    this.apparentWindAngle,
    this.apparentWindSpeed,
    this.trueWindSpeed,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
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
              const Expanded(
                child: Text('WIND',
                    style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.0),
                    overflow: TextOverflow.ellipsis),
              ),
              if (onTap != null)
                const Icon(Icons.expand_more_rounded,
                    size: 14, color: AppColors.textDim),
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

    if (onTap == null) return card;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        splashColor: AppColors.teal.withAlpha(30),
        highlightColor: AppColors.teal.withAlpha(15),
        child: card,
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
