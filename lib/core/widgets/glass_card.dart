import 'dart:ui';
import 'package:flutter/material.dart';

/// iOS / macOS-style frosted glass card.
///
/// Requires a rich background (gradients, blobs) behind it so the
/// BackdropFilter blur has something interesting to render.
class GlassCard extends StatelessWidget {
  final Widget child;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  /// Optional accent tint that bleeds through the glass.
  final Color? tint;
  final double blur;
  final double opacity;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    this.borderRadius,
    this.padding,
    this.tint,
    this.blur = 18,
    this.opacity = 0.09,
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
          color: Colors.white.withOpacity(0.18),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 28,
            offset: const Offset(0, 8),
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
                  color.withOpacity(opacity + 0.04),
                  color.withOpacity(opacity * 0.4),
                ],
              ),
            ),
            child: child,
          ),
        ),
      ),
    );

    if (onTap != null) {
      card = GestureDetector(
        onTap: onTap,
        child: card,
      );
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
        // Base deep navy
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF020D1B), Color(0xFF010810)],
            ),
          ),
        ),
        // Cyan glow — top-left
        _blob(size: 500, color: const Color(0xFF00D9FF), opacity: 0.13,
            top: -120, left: -80),
        // Blue glow — top-right
        _blob(size: 320, color: const Color(0xFF0A84FF), opacity: 0.11,
            top: -60, right: -60),
        // Teal glow — bottom-right
        _blob(size: 400, color: const Color(0xFF00B4A0), opacity: 0.10,
            right: -80, bottom: 80),
        // Purple hint — bottom-left
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
      top: top,
      left: left,
      right: right,
      bottom: bottom,
      child: IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                color.withOpacity(opacity),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
