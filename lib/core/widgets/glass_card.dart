import 'dart:ui';
import 'package:flutter/material.dart';

/// Apple Liquid Glass card — manual implementation.
///
/// The primary visible effect is refraction / specular glare (like clear glass),
/// not blur. Heavy blur (18σ) produces frosted glass; we use 2σ here so
/// the background shows through (transparent/clear glass look).
///   blur sigma:  2σ  — barely blurs, preserves background readability
///   tint:        0x26FFFFFF = 15% white fill for subtle separation
///   specular:    42% white, -35° diagonal upper-left glare
///   fresnel rim: 55% at edges fading to 0 toward center
class GlassCard extends StatelessWidget {
  final Widget child;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final Color? tint;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    this.borderRadius,
    this.padding,
    this.tint,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(22);
    // 15% white tint — enough for contrast without hiding the background
    final tintColor = tint ?? const Color(0x26FFFFFF);

    Widget card = Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: Colors.white.withOpacity(0.25), width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.28),
            blurRadius: 32,
            spreadRadius: -4,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          // 2σ — barely blurs the background so it reads as clear glass,
          // not frosted glass.  The specular + Fresnel provide the glassy look.
          filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
          child: CustomPaint(
            painter: _LiquidGlassPainter(
              borderRadius: radius,
              tint: tintColor,
            ),
            child: Container(
              padding: padding ?? const EdgeInsets.all(16),
              child: child,
            ),
          ),
        ),
      ),
    );

    if (onTap != null) {
      card = GestureDetector(onTap: onTap, child: card);
    }
    return card;
  }
}

/// Paints the liquid glass optical effects:
/// tint fill, diagonal specular glare, Fresnel rim glow.
class _LiquidGlassPainter extends CustomPainter {
  final BorderRadius borderRadius;
  final Color tint;

  const _LiquidGlassPainter({required this.borderRadius, required this.tint});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = borderRadius.toRRect(rect);

    canvas.save();
    canvas.clipRRect(rrect);

    // 1. Base tint — 13% white (Apple documented value)
    canvas.drawRRect(rrect, Paint()..color = tint);

    // 2. Fresnel rim glow — edges brighter (power-3.5 falloff toward center)
    // Simulated as a radial gradient from all edges inward
    const fresnelOpacity = 0.55;
    final fresnelPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 1.0,
        colors: [
          Colors.transparent,
          Colors.white.withOpacity(fresnelOpacity * 0.3),
          Colors.white.withOpacity(fresnelOpacity * 0.7),
          Colors.white.withOpacity(fresnelOpacity),
        ],
        stops: const [0.0, 0.55, 0.80, 1.0],
      ).createShader(rect);
    canvas.drawRRect(rrect, fresnelPaint);

    // 3. Specular highlight — diagonal white glare at -35°
    // 42% peak opacity (stronger than before so glass reads clearly with low blur)
    final specularPaint = Paint()
      ..shader = LinearGradient(
        begin: const Alignment(-1.2, -1.2),
        end: const Alignment(0.8, 0.8),
        colors: [
          Colors.white.withOpacity(0.42),
          Colors.white.withOpacity(0.22),
          Colors.white.withOpacity(0.06),
          Colors.transparent,
        ],
        stops: const [0.0, 0.22, 0.48, 1.0],
      ).createShader(rect);
    canvas.drawRRect(rrect, specularPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_LiquidGlassPainter old) =>
      old.tint != tint || old.borderRadius != borderRadius;
}

/// Full-screen aurora gradient background.
class AuroraBackground extends StatelessWidget {
  const AuroraBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF020D1B), Color(0xFF010810)],
            ),
          ),
        ),
        _blob(size: 500, color: const Color(0xFF00D9FF), opacity: 0.13,
            top: -120, left: -80),
        _blob(size: 320, color: const Color(0xFF0A84FF), opacity: 0.11,
            top: -60, right: -60),
        _blob(size: 400, color: const Color(0xFF00B4A0), opacity: 0.10,
            right: -80, bottom: 80),
        _blob(size: 280, color: const Color(0xFF5E5CE6), opacity: 0.08,
            left: -40, bottom: 160),
      ],
    );
  }

  Widget _blob({required double size, required Color color,
      required double opacity, double? top, double? left,
      double? right, double? bottom}) {
    return Positioned(
      top: top, left: left, right: right, bottom: bottom,
      child: IgnorePointer(
        child: Container(
          width: size, height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [color.withOpacity(opacity), Colors.transparent],
            ),
          ),
        ),
      ),
    );
  }
}
