import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/vessel_provider.dart';
import '../../../core/providers/connection_provider.dart';
import '../../../core/providers/locale_provider.dart';
import '../../../core/theme/app_colors.dart';

class VesselStatusBar extends ConsumerWidget {
  const VesselStatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vessel = ref.watch(vesselProvider);
    final conn   = ref.watch(connectionProvider);
    final s      = ref.watch(stringsProvider);

    final sogStr = vessel.speedOverGround != null
        ? '${vessel.speedOverGround!.toStringAsFixed(1)} kn'
        : '—';
    final cogStr = vessel.courseOverGround != null
        ? '${vessel.courseOverGround!.toStringAsFixed(0)}°'
        : '—';
    final dStr = vessel.depthBelowKeel != null
        ? '${vessel.depthBelowKeel!.toStringAsFixed(1)} m'
        : '—';
    final twsStr = vessel.trueWindSpeed != null
        ? '${vessel.trueWindSpeed!.toStringAsFixed(0)} kn'
        : '—';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            height: 58,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withOpacity(0.10),
                  Colors.white.withOpacity(0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Colors.white.withOpacity(0.15),
                width: 0.8,
              ),
            ),
            child: Row(
              children: [
                _Cell(label: s.sog,   value: sogStr),
                _vDivider(),
                _Cell(label: s.cog,   value: cogStr),
                _vDivider(),
                _Cell(label: s.depth, value: dStr),
                _vDivider(),
                _Cell(label: s.tws,   value: twsStr),
                _vDivider(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      _Dot(active: conn.isSignalKConnected,
                           label: 'SK', color: AppColors.cyan),
                      const SizedBox(width: 10),
                      _Dot(active: conn.isLanSyncActive,
                           label: 'LAN', color: AppColors.teal),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _vDivider() => Container(
        width: 0.6,
        height: 26,
        color: Colors.white.withOpacity(0.12),
      );
}

class _Cell extends StatelessWidget {
  final String label;
  final String value;
  const _Cell({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.45),
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: Colors.white.withOpacity(0.90),
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final bool active;
  final String label;
  final Color color;
  const _Dot({required this.active, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? color : Colors.white.withOpacity(0.2),
            boxShadow: active
                ? [BoxShadow(color: color.withOpacity(0.7), blurRadius: 6)]
                : null,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.35),
            fontSize: 8,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
      ],
    );
  }
}
