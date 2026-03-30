import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

class AppTileData {
  final String id;
  final String label;
  final IconData icon;
  final Color accentColor;
  final String route;
  final String? badge; // optional live value snippet
  final bool isStub; // greyed-out placeholder

  const AppTileData({
    required this.id,
    required this.label,
    required this.icon,
    required this.accentColor,
    required this.route,
    this.badge,
    this.isStub = false,
  });
}

class AppTile extends StatelessWidget {
  final AppTileData data;
  final VoidCallback onTap;

  const AppTile({super.key, required this.data, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = data.isStub ? AppColors.inactive : data.accentColor;

    return GestureDetector(
      onTap: data.isStub ? null : onTap,
      child: AnimatedScale(
        scale: 1.0,
        duration: const Duration(milliseconds: 120),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border, width: 1),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.cardBg,
                Color.lerp(AppColors.cardBg, accent, 0.08)!,
              ],
            ),
          ),
          child: Stack(
            children: [
              // Subtle corner accent line
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      accent.withAlpha(180),
                      accent.withAlpha(0),
                    ]),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Icon
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: accent.withAlpha(28),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(data.icon, color: accent, size: 24),
                    ),
                    const Spacer(),
                    // Label
                    Text(
                      data.label,
                      style: TextStyle(
                        color: data.isStub
                            ? AppColors.textMuted
                            : AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // Badge / live value
                    if (data.badge != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        data.badge!,
                        style: TextStyle(
                          color: accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (data.isStub) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Coming soon',
                        style: TextStyle(
                          color: AppColors.textDim,
                          fontSize: 10,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
