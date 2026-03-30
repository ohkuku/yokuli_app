import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/providers/vessel_provider.dart';
import '../../../core/providers/connection_provider.dart';

class VesselStatusBar extends ConsumerWidget {
  const VesselStatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vessel = ref.watch(vesselProvider);
    final conn = ref.watch(connectionProvider);

    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          _StatusCell(
            label: 'SOG',
            value: vessel.speedOverGround != null
                ? '${vessel.speedOverGround!.toStringAsFixed(1)} kn'
                : '—',
            icon: Icons.speed,
          ),
          _divider(),
          _StatusCell(
            label: 'COG',
            value: vessel.courseOverGround != null
                ? '${vessel.courseOverGround!.toStringAsFixed(0)}°'
                : '—',
            icon: Icons.navigation,
          ),
          _divider(),
          _StatusCell(
            label: 'DEPTH',
            value: vessel.depthBelowKeel != null
                ? '${vessel.depthBelowKeel!.toStringAsFixed(1)} m'
                : '—',
            icon: Icons.water,
          ),
          _divider(),
          _StatusCell(
            label: 'TWS',
            value: vessel.trueWindSpeed != null
                ? '${vessel.trueWindSpeed!.toStringAsFixed(0)} kn'
                : '—',
            icon: Icons.air,
          ),
          _divider(),
          // Connection dots
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _ConnDot(
                  active: conn.isSignalKConnected,
                  label: 'SK',
                  color: AppColors.cyan,
                ),
                const SizedBox(width: 8),
                _ConnDot(
                  active: conn.isLanSyncActive,
                  label: 'LAN',
                  color: AppColors.teal,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 28,
        color: AppColors.border,
      );
}

class _StatusCell extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatusCell({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnDot extends StatelessWidget {
  final bool active;
  final String label;
  final Color color;

  const _ConnDot({required this.active, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? color : AppColors.inactive,
            boxShadow: active
                ? [BoxShadow(color: color.withAlpha(160), blurRadius: 6, spreadRadius: 1)]
                : null,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 8,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}
