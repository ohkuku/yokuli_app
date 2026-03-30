import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/providers/vessel_provider.dart';
import '../../../core/providers/locale_provider.dart';
import '../../../core/l10n/strings.dart';
import '../widgets/instrument_card.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vessel = ref.watch(vesselProvider);
    final isTablet = MediaQuery.of(context).size.width > 600;
    final s = ref.watch(stringsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(s.dashboard),
        actions: [
          // Last update indicator
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: _DataAgeIndicator(lastUpdated: vessel.lastUpdated, s: s),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(12),
              sliver: SliverGrid(
                delegate: SliverChildListDelegate([
                  // Speed Over Ground
                  InstrumentCard(
                    label: s.speedSOG.toUpperCase(),
                    value: vessel.speedOverGround?.toStringAsFixed(1) ?? '—',
                    unit: 'kn',
                    icon: Icons.speed_rounded,
                    accentColor: AppColors.cyan,
                    gaugeValue: vessel.speedOverGround != null
                        ? (vessel.speedOverGround! / 20).clamp(0, 1)
                        : null,
                  ),

                  // Compass / heading
                  CompassCard(
                    headingDeg: vessel.heading,
                    cogDeg: vessel.courseOverGround,
                  ),

                  // True Wind Speed
                  InstrumentCard(
                    label: s.trueWind.toUpperCase(),
                    value: vessel.trueWindSpeed?.toStringAsFixed(1) ?? '—',
                    unit: 'kn',
                    icon: Icons.air_rounded,
                    accentColor: AppColors.teal,
                    gaugeValue: vessel.trueWindSpeed != null
                        ? (vessel.trueWindSpeed! / 40).clamp(0, 1)
                        : null,
                    gaugeColor: _windSpeedColor(vessel.trueWindSpeed),
                  ),

                  // Wind angle
                  WindAngleCard(
                    apparentWindAngle: vessel.apparentWindAngle,
                    apparentWindSpeed: vessel.apparentWindSpeed,
                    trueWindSpeed: vessel.trueWindSpeed,
                  ),

                  // Depth
                  InstrumentCard(
                    label: s.depthKeel.toUpperCase(),
                    value: vessel.depthBelowKeel?.toStringAsFixed(1) ?? '—',
                    unit: 'm',
                    icon: Icons.water_rounded,
                    accentColor: _depthColor(vessel.depthBelowKeel),
                    gaugeValue: vessel.depthBelowKeel != null
                        ? (vessel.depthBelowKeel! / 30).clamp(0, 1)
                        : null,
                    gaugeColor: _depthColor(vessel.depthBelowKeel),
                  ),

                  // GPS position
                  _GpsCard(
                    lat: vessel.position?.latitude,
                    lon: vessel.position?.longitude,
                    s: s,
                  ),
                ]),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: isTablet ? 3 : 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.05,
                ),
              ),
            ),

            // Batteries section
            if (vessel.batteries.isNotEmpty) ...[
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    s.power.toUpperCase(),
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                sliver: SliverGrid(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final battery =
                          vessel.batteries.values.elementAt(index);
                      final soc = battery.stateOfCharge ?? 0;
                      return InstrumentCard(
                        label: battery.name.toUpperCase(),
                        value: battery.voltage?.toStringAsFixed(1) ?? '—',
                        unit: 'V',
                        icon: Icons.battery_charging_full_rounded,
                        accentColor: _batteryColor(soc),
                        gaugeValue: soc,
                        gaugeColor: _batteryColor(soc),
                      );
                    },
                    childCount: vessel.batteries.length,
                  ),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: isTablet ? 4 : 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.2,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _windSpeedColor(double? kn) {
    if (kn == null) return AppColors.teal;
    if (kn < 15) return AppColors.success;
    if (kn < 25) return AppColors.warning;
    return AppColors.danger;
  }

  Color _depthColor(double? m) {
    if (m == null) return AppColors.cyan;
    if (m > 5) return AppColors.success;
    if (m > 2) return AppColors.warning;
    return AppColors.danger;
  }

  Color _batteryColor(double soc) {
    if (soc > 0.5) return AppColors.success;
    if (soc > 0.25) return AppColors.warning;
    return AppColors.danger;
  }
}

class _GpsCard extends StatelessWidget {
  final double? lat;
  final double? lon;
  final S s;

  const _GpsCard({this.lat, this.lon, required this.s});

  String _formatDMS(double deg, bool isLat) {
    final dir = isLat ? (deg >= 0 ? 'N' : 'S') : (deg >= 0 ? 'E' : 'W');
    final abs = deg.abs();
    final d = abs.floor();
    final mFull = (abs - d) * 60;
    final m = mFull.floor();
    final s = ((mFull - m) * 60).toStringAsFixed(1);
    return "$d° $m' $s\" $dir";
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.gps_fixed_rounded, size: 14, color: AppColors.success),
            const SizedBox(width: 6),
            Text(s.position.toUpperCase(),
                style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.0)),
          ]),
          const Spacer(),
          if (lat != null && lon != null) ...[
            Text(
              _formatDMS(lat!, true),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatDMS(lon!, false),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ] else
            Text(s.noFix,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 16)),
        ],
      ),
    );
  }
}

class _DataAgeIndicator extends StatelessWidget {
  final DateTime lastUpdated;
  final S s;

  const _DataAgeIndicator({required this.lastUpdated, required this.s});

  @override
  Widget build(BuildContext context) {
    final ageMs = DateTime.now().difference(lastUpdated).inMilliseconds;
    final isStale = ageMs > 5000;
    final isVeryStale = ageMs > 30000;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isVeryStale
            ? AppColors.danger.withAlpha(30)
            : isStale
                ? AppColors.warning.withAlpha(30)
                : AppColors.success.withAlpha(30),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isVeryStale
              ? AppColors.danger.withAlpha(80)
              : isStale
                  ? AppColors.warning.withAlpha(80)
                  : AppColors.success.withAlpha(80),
        ),
      ),
      child: Row(children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isVeryStale
                ? AppColors.danger
                : isStale
                    ? AppColors.warning
                    : AppColors.success,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          isVeryStale
              ? s.dataStale
              : isStale
                  ? s.dataSlow
                  : s.dataLive,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isVeryStale
                ? AppColors.danger
                : isStale
                    ? AppColors.warning
                    : AppColors.success,
          ),
        ),
      ]),
    );
  }
}
