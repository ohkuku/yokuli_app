import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

class AppTileData {
  final String id;
  final String label;
  final IconData icon;
  final Color accentColor;
  final String route;
  final String? badge;
  final bool isStub;
  final int notificationCount;

  const AppTileData({
    required this.id,
    required this.label,
    required this.icon,
    required this.accentColor,
    required this.route,
    this.badge,
    this.isStub = false,
    this.notificationCount = 0,
  });
}

class AppTile extends StatefulWidget {
  final AppTileData data;
  final VoidCallback onTap;

  const AppTile({super.key, required this.data, required this.onTap});

  @override
  State<AppTile> createState() => _AppTileState();
}

class _AppTileState extends State<AppTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.93).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.data.isStub
        ? Colors.white.withOpacity(0.3)
        : widget.data.accentColor;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.data.isStub ? null : (_) => _ctrl.forward(),
      onTapUp: widget.data.isStub
          ? null
          : (_) {
              _ctrl.reverse();
              widget.onTap();
            },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: _GlassTile(
          accent: accent,
          isStub: widget.data.isStub,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon badge (with optional notification count)
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(13),
                      color: accent.withOpacity(0.18),
                      border: Border.all(
                        color: accent.withOpacity(0.30),
                        width: 0.8,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withOpacity(0.25),
                          blurRadius: 12,
                          spreadRadius: -2,
                        ),
                      ],
                    ),
                    child: Icon(
                      widget.data.icon,
                      color: widget.data.isStub
                          ? Colors.white.withOpacity(0.35)
                          : accent,
                      size: 22,
                    ),
                  ),
                  if (widget.data.notificationCount > 0)
                    Positioned(
                      top: -4,
                      right: -4,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: const BoxDecoration(
                          color: Color(0xFFFF3B30),
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          widget.data.notificationCount > 99
                              ? '99+'
                              : widget.data.notificationCount.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              const Spacer(),
              // Label
              Text(
                widget.data.label,
                style: TextStyle(
                  color: widget.data.isStub
                      ? Colors.white.withOpacity(0.35)
                      : Colors.white.withOpacity(0.92),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.1,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              // Badge / sub-line
              if (widget.data.badge != null)
                Text(
                  widget.data.badge!,
                  style: TextStyle(
                    color: accent.withOpacity(0.85),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
              else if (widget.data.isStub)
                Text(
                  'Coming soon',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.22),
                    fontSize: 10,
                    fontStyle: FontStyle.italic,
                  ),
                )
              else
                const SizedBox(height: 13), // maintain height
            ],
          ),
        ),
      ),
    );
  }
}

/// Glass tile using [BackdropFilter] + [CustomPaint] shimmer so the effect
/// stays fully alive on Android even when the GPU pipeline is idle.
///
/// The old [GlassContainer] (GLSL shader) froze on Android when scroll stopped
/// because Flutter's optimizer skips repaints when the widget tree is
/// bit-for-bit identical across frames.  [BackdropFilter] always re-composites
/// from the live background, and the [_LiquidShimmerPainter] outputs slightly
/// different pixels every tick (via `shouldRepaint`) keeping the frame pipeline
/// active.
class _GlassTile extends StatefulWidget {
  final Color accent;
  final bool isStub;
  final Widget child;

  const _GlassTile({
    required this.accent,
    required this.isStub,
    required this.child,
  });

  @override
  State<_GlassTile> createState() => _GlassTileState();
}

class _GlassTileState extends State<_GlassTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ticker,
      builder: (_, __) {
        final t = _ticker.value;
        final accent = widget.accent;
        final isStub = widget.isStub;
        return ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              // ① Blur — always reads live pixels; never frozen on Android.
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: isStub ? 6 : 10,
                    sigmaY: isStub ? 6 : 10,
                    tileMode: TileMode.mirror,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
              // ② Glass tint + border
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: isStub
                        ? Colors.white.withOpacity(0.06)
                        : accent.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.14),
                      width: 0.8,
                    ),
                  ),
                ),
              ),
              // ③ Animated shimmer — changes every frame so Flutter never
              //    skips compositing this subtree.
              Positioned.fill(
                child: CustomPaint(
                  painter: _LiquidShimmerPainter(
                    t: t,
                    accent: accent,
                    isStub: isStub,
                  ),
                ),
              ),
              // ④ Tile content
              Padding(
                padding: const EdgeInsets.all(16),
                child: widget.child,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Draws a top-edge specular highlight and a slow-moving accent shimmer.
/// Because [t] changes every frame, [shouldRepaint] always returns true,
/// ensuring the layer is re-drawn each vsync tick.
class _LiquidShimmerPainter extends CustomPainter {
  final double t;
  final Color accent;
  final bool isStub;

  const _LiquidShimmerPainter({
    required this.t,
    required this.accent,
    required this.isStub,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w, h),
      const Radius.circular(20),
    );

    // Top-edge specular highlight — pulses gently.
    final highlightAlpha = isStub
        ? 0.07
        : 0.16 + math.sin(t * 2 * math.pi) * 0.05;
    final highlightPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withOpacity(highlightAlpha),
          Colors.white.withOpacity(0.0),
        ],
        stops: const [0.0, 0.45],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawRRect(rrect, highlightPaint);

    if (!isStub) {
      // Slow-drifting accent shimmer band.
      final shimmerCy = -0.6 + math.sin(t * 2 * math.pi) * 0.25;
      final shimmerPaint = Paint()
        ..shader = RadialGradient(
          center: Alignment(0.0, shimmerCy),
          radius: 0.75,
          colors: [
            accent.withOpacity(0.13),
            accent.withOpacity(0.0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, w, h));
      canvas.drawRRect(rrect, shimmerPaint);
    }
  }

  @override
  bool shouldRepaint(_LiquidShimmerPainter old) => old.t != t;
}
