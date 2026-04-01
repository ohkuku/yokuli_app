import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/vessel_state.dart';
import '../../../core/providers/vessel_provider.dart';
import '../../../core/providers/connection_provider.dart';
import '../../../core/providers/locale_provider.dart';
import '../../../core/theme/app_colors.dart';

/// How fresh the Signal K data stream is.
enum _SkQuality {
  /// Receiving data within the last 5 seconds.
  good,
  /// Connected but no data for 5–30 seconds (stale).
  stale,
  /// Disconnected, error, or no data for > 30 seconds.
  dead,
}

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

    // Derive Signal K quality from connection status + data staleness.
    final skQuality = _skQualityFor(conn, vessel);

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
                      _SkQualityDot(quality: skQuality),
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

  static _SkQuality _skQualityFor(
    AppConnectionState conn,
    VesselState vessel,
  ) {
    if (!conn.isSignalKConnected) return _SkQuality.dead;

    // epoch-0 means no data has arrived yet
    if (vessel.lastUpdated.millisecondsSinceEpoch == 0) return _SkQuality.dead;

    final age = DateTime.now().difference(vessel.lastUpdated);
    if (age.inSeconds <= 5) return _SkQuality.good;
    if (age.inSeconds <= 30) return _SkQuality.stale;
    return _SkQuality.dead;
  }
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

/// Three-state Signal K connection quality indicator:
///   - Green  = connected, receiving data < 5 s ago
///   - Yellow = connected but no data for 5–30 s (stale)
///   - Red    = disconnected / error / no data > 30 s
class _SkQualityDot extends StatelessWidget {
  final _SkQuality quality;
  const _SkQualityDot({required this.quality});

  @override
  Widget build(BuildContext context) {
    final Color dotColor;
    switch (quality) {
      case _SkQuality.good:
        dotColor = AppColors.cyan;
        break;
      case _SkQuality.stale:
        dotColor = const Color(0xFFFFBF00); // amber/yellow
        break;
      case _SkQuality.dead:
        dotColor = const Color(0xFFE53935); // red
        break;
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: dotColor,
            boxShadow: [
              BoxShadow(color: dotColor.withOpacity(0.65), blurRadius: 6),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'SK',
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
