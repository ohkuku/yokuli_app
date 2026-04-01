import 'package:flutter/material.dart';
import 'package:liquid_glass_lts/liquid_glass_lts.dart';

/// iOS 26 Liquid Glass card using the liquid_glass_lts package.
///
/// Implements authentic Apple Liquid Glass physics:
/// refraction (UV lens distortion), Fresnel rim glow,
/// diagonal specular highlight, chromatic dispersion, and
/// subtle blur — in that order of visual importance.
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
    final r = borderRadius?.topLeft.x ?? 22.0;
    final tintColor = tint?.withOpacity(0.08) ?? const Color(0x22FFFFFF);

    Widget card = LiquidGlassWidget(
      config: LiquidGlassConfig(
        borderRadius: r,
        blur: const BlurConfig(sigma: 18.0),
        tint: TintConfig(color: tintColor),
        fresnel: const FresnelConfig(intensity: 0.55, power: 3.5),
        glare: const GlareConfig(opacity: 0.35, angle: -35.0, size: 0.6, hardness: 0.25),
        refraction: const RefractionConfig(strength: 0.18, dispersion: 0.012, edgeSoftness: 0.06),
        shadows: [
          BoxShadow(
            color: Colors.black.withOpacity(0.28),
            blurRadius: 32,
            spreadRadius: -4,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(16),
        child: child,
      ),
    );

    if (onTap != null) {
      card = GestureDetector(onTap: onTap, child: card);
    }

    return card;
  }
}

/// Full-screen aurora gradient background.
/// Place this behind all glass cards.
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

  Widget _blob({
    required double size,
    required Color color,
    required double opacity,
    double? top,
    double? left,
    double? right,
    double? bottom,
  }) {
    return Positioned(
      top: top, left: left, right: right, bottom: bottom,
      child: IgnorePointer(
        child: Container(
          width: size,
          height: size,
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
