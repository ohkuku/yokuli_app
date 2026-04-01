import 'dart:ui';
import 'package:flutter/material.dart';

/// iOS 26-style liquid glass card.
///
/// Clear glass — nearly transparent, no heavy blur.
/// Visual depth comes from specular edge highlights and a subtle inner caustic,
/// not frosting. Requires a rich colourful background to show through.
class GlassCard extends StatelessWidget {
  final Widget child;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final Color? tint;
  /// Minimal haze — keeps text legible on very busy backgrounds.
  final double blur;
  final double opacity;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    this.borderRadius,
    this.padding,
    this.tint,
    this.blur = 12,
    this.opacity = 0.18,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(22);
    final color = tint ?? Colors.white;

    Widget card = Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(
          color: Colors.white.withOpacity(0.22),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.28),
            blurRadius: 40,
            spreadRadius: -4,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.10),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  color.withOpacity(opacity),
                  color.withOpacity(opacity * 0.5),
                ],
              ),
            ),
            foregroundDecoration: BoxDecoration(
              // Top specular edge + inner caustic combined
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.0, 0.04, 0.30, 1.0],
                colors: [
                  Colors.white.withOpacity(0.55), // bright top edge (specular)
                  Colors.white.withOpacity(0.20), // caustic fade
                  Colors.white.withOpacity(0.04),
                  Colors.transparent,
                ],
              ),
            ),
            child: child,
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
