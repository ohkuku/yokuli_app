import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

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

class _GlassTile extends StatelessWidget {
  final Color accent;
  final bool isStub;
  final Widget child;

  const _GlassTile({
    required this.accent,
    required this.isStub,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(22));
    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        // Gradient border: bright top (light source), faint bottom
        border: Border.all(
          color: isStub
              ? Colors.white.withOpacity(0.08)
              : Colors.white.withOpacity(0.20),
          width: 0.8,
        ),
        boxShadow: isStub
            ? null
            : [
                BoxShadow(
                  color: accent.withOpacity(0.15),
                  blurRadius: 24,
                  spreadRadius: -4,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.22),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          // Moderate blur — separates tile from background without heavy frosting
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isStub
                    ? [
                        Colors.white.withOpacity(0.08),
                        Colors.white.withOpacity(0.04),
                      ]
                    : [
                        accent.withOpacity(0.20),
                        Colors.white.withOpacity(0.10),
                      ],
              ),
            ),
            foregroundDecoration: isStub
                ? null
                : BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.0, 0.04, 0.35, 1.0],
                      colors: [
                        Colors.white.withOpacity(0.50),
                        Colors.white.withOpacity(0.18),
                        Colors.white.withOpacity(0.03),
                        Colors.transparent,
                      ],
                    ),
                  ),
            child: child,
          ),
        ),
      ),
    );
  }
}
