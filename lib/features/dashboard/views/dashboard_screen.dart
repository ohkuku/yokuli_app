import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/providers/vessel_provider.dart';
import '../../../core/providers/power_history_provider.dart';
import '../../../core/models/vessel_state.dart';
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
                    onTap: () => showInstrumentDetail(context,
                      title: s.speedSOG,
                      content: _SogDetail(sog: vessel.speedOverGround),
                    ),
                  ),

                  // Compass / heading
                  CompassCard(
                    headingDeg: vessel.heading,
                    cogDeg: vessel.courseOverGround,
                    onTap: () => showInstrumentDetail(context,
                      title: 'HEADING / COG',
                      content: _HeadingDetail(
                        heading: vessel.heading,
                        cog: vessel.courseOverGround,
                      ),
                    ),
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
                    onTap: () => showInstrumentDetail(context,
                      title: s.trueWind,
                      content: _WindDetail(
                        trueWind: vessel.trueWindSpeed,
                        apparentWind: vessel.apparentWindSpeed,
                        windAngle: vessel.apparentWindAngle,
                      ),
                    ),
                  ),

                  // Wind angle
                  WindAngleCard(
                    apparentWindAngle: vessel.apparentWindAngle,
                    apparentWindSpeed: vessel.apparentWindSpeed,
                    trueWindSpeed: vessel.trueWindSpeed,
                    onTap: () => showInstrumentDetail(context,
                      title: '风角',
                      content: _WindAngleDetail(
                        angle: vessel.apparentWindAngle,
                        trueWind: vessel.trueWindSpeed,
                        apparentWind: vessel.apparentWindSpeed,
                      ),
                    ),
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
                    onTap: () => showInstrumentDetail(context,
                      title: s.depthKeel,
                      content: _DepthDetail(depth: vessel.depthBelowKeel),
                    ),
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
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
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
                      final entry =
                          vessel.batteries.entries.elementAt(index);
                      final battery = entry.value;
                      final soc = battery.stateOfCharge ?? 0;
                      return InstrumentCard(
                        label: battery.name.toUpperCase(),
                        value: battery.voltage?.toStringAsFixed(1) ?? '—',
                        unit: 'V',
                        icon: Icons.battery_charging_full_rounded,
                        accentColor: _batteryColor(soc),
                        gaugeValue: soc,
                        gaugeColor: _batteryColor(soc),
                        onTap: () => showInstrumentDetail(context,
                          title: battery.name,
                          content: _BatteryDetail(
                            batteryId: entry.key,
                            battery: battery,
                          ),
                        ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Detail sheet content widgets
// ─────────────────────────────────────────────────────────────────────────────

/// Beaufort scale: returns (force, description) for a wind speed in knots.
({int force, String desc, String sea}) _beaufort(double kn) {
  if (kn < 1) return (force: 0, desc: 'Calm', sea: 'Sea like a mirror');
  if (kn < 4) return (force: 1, desc: 'Light Air', sea: 'Ripples, no foam');
  if (kn < 7) return (force: 2, desc: 'Light Breeze', sea: 'Small wavelets');
  if (kn < 11) return (force: 3, desc: 'Gentle Breeze', sea: 'Large wavelets, crests begin');
  if (kn < 16) return (force: 4, desc: 'Moderate Breeze', sea: 'Small waves, frequent whitecaps');
  if (kn < 22) return (force: 5, desc: 'Fresh Breeze', sea: 'Moderate waves, many whitecaps');
  if (kn < 28) return (force: 6, desc: 'Strong Breeze', sea: 'Large waves, spray');
  if (kn < 34) return (force: 7, desc: 'Near Gale', sea: 'Sea heaps up, foam streaks');
  if (kn < 41) return (force: 8, desc: 'Gale', sea: 'Moderately high waves, well-marked streaks');
  if (kn < 48) return (force: 9, desc: 'Severe Gale', sea: 'High waves, rolling, spray');
  if (kn < 56) return (force: 10, desc: 'Storm', sea: 'Very high waves, surface white');
  if (kn < 64) return (force: 11, desc: 'Violent Storm', sea: 'Exceptionally high waves');
  return (force: 12, desc: 'Hurricane', sea: 'Air filled with foam, sea white');
}

Widget _detailRow(String label, String value, {Color? valueColor}) =>
    Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13)),
          Text(value,
              style: TextStyle(
                  color: valueColor ?? AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );

// ── SOG detail ──────────────────────────────────────────────────────────────
class _SogDetail extends StatelessWidget {
  final double? sog;
  const _SogDetail({this.sog});

  @override
  Widget build(BuildContext context) {
    final bf = sog != null ? _beaufort(sog!) : null;
    final classification = sog == null
        ? '—'
        : sog! < 3
            ? '慢速 / 泊位速度'
            : sog! < 6
                ? '正常航速'
                : sog! < 10
                    ? '高速航行'
                    : '极速';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _detailRow('当前航速', sog != null ? '${sog!.toStringAsFixed(2)} kn' : '—'),
        _detailRow('类型', classification),
        if (bf != null) ...[
          _detailRow('对应风力等级', 'Force ${bf.force} — ${bf.desc}'),
          _detailRow('海况参考', bf.sea),
        ],
        const SizedBox(height: 16),
        const Text('Beaufort 速度对照',
            style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.0)),
        const SizedBox(height: 8),
        const _BeaufortTable(),
      ],
    );
  }
}

class _BeaufortTable extends StatelessWidget {
  const _BeaufortTable();
  @override
  Widget build(BuildContext context) {
    const rows = [
      ('0', '< 1 kn', 'Calm'),
      ('1-2', '1-6 kn', 'Light wind'),
      ('3-4', '7-16 kn', 'Gentle-Moderate'),
      ('5-6', '17-27 kn', 'Fresh-Strong'),
      ('7-8', '28-40 kn', 'Near-Full Gale'),
      ('9-10', '41-55 kn', 'Severe-Storm'),
      ('11-12', '56+ kn', 'Violent-Hurricane'),
    ];
    return Column(
      children: rows.map((r) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          SizedBox(width: 44,
              child: Text('F${r.$1}',
                  style: const TextStyle(
                      color: AppColors.cyan,
                      fontSize: 12,
                      fontWeight: FontWeight.w700))),
          SizedBox(width: 80,
              child: Text(r.$2,
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 12))),
          Expanded(child: Text(r.$3,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12))),
        ]),
      )).toList(),
    );
  }
}

// ── Heading detail ───────────────────────────────────────────────────────────
class _HeadingDetail extends StatelessWidget {
  final double? heading;
  final double? cog;
  const _HeadingDetail({this.heading, this.cog});

  String _cardinal(double deg) {
    const dirs = ['N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
                  'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'];
    final idx = ((deg % 360) / 22.5).round() % 16;
    const full = ['North', 'North-Northeast', 'Northeast', 'East-Northeast',
                  'East', 'East-Southeast', 'Southeast', 'South-Southeast',
                  'South', 'South-Southwest', 'Southwest', 'West-Southwest',
                  'West', 'West-Northwest', 'Northwest', 'North-Northwest'];
    return '${dirs[idx]} — ${full[idx]}';
  }

  @override
  Widget build(BuildContext context) {
    final diff = (heading != null && cog != null)
        ? (cog! - heading!).remainder(360)
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (heading != null)
          _detailRow('船首向 (HDG)', '${heading!.toStringAsFixed(1)}°T'),
        if (cog != null)
          _detailRow('对地航向 (COG)', '${cog!.toStringAsFixed(1)}°T'),
        if (heading != null)
          _detailRow('方位', _cardinal(heading!)),
        if (diff != null)
          _detailRow('偏差 HDG→COG',
              '${diff.toStringAsFixed(1)}°',
              valueColor: diff.abs() > 10 ? AppColors.warning : AppColors.success),
        if (diff != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              diff.abs() < 2
                  ? '航向稳定，几乎无偏差'
                  : diff > 0
                      ? '右流/风压：对地航向偏右 ${diff.abs().toStringAsFixed(0)}°'
                      : '左流/风压：对地航向偏左 ${diff.abs().toStringAsFixed(0)}°',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

// ── Wind detail ──────────────────────────────────────────────────────────────
class _WindDetail extends StatelessWidget {
  final double? trueWind;
  final double? apparentWind;
  final double? windAngle;
  const _WindDetail({this.trueWind, this.apparentWind, this.windAngle});

  @override
  Widget build(BuildContext context) {
    final bf = trueWind != null ? _beaufort(trueWind!) : null;
    final bfColor = bf == null ? AppColors.textPrimary
        : bf.force <= 3 ? AppColors.success
        : bf.force <= 5 ? AppColors.warning
        : AppColors.danger;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (trueWind != null)
          _detailRow('真风速', '${trueWind!.toStringAsFixed(1)} kn'),
        if (apparentWind != null)
          _detailRow('视风速', '${apparentWind!.toStringAsFixed(1)} kn'),
        if (windAngle != null)
          _detailRow('视风角', '${windAngle!.toStringAsFixed(0)}°'),
        if (bf != null) ...[
          const Divider(color: AppColors.border, height: 24),
          _detailRow('Beaufort',
              'Force ${bf.force} — ${bf.desc}',
              valueColor: bfColor),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(bf.sea,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
          ),
          if (bf.force >= 6)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.danger.withAlpha(20),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.danger.withAlpha(80)),
              ),
              child: Row(children: [
                const Icon(Icons.warning_rounded,
                    color: AppColors.danger, size: 14),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  bf.force >= 8
                      ? '⚠ 强风警告 — 考虑缩帆或寻求避风'
                      : '注意：大风条件，注意航行安全',
                  style: const TextStyle(
                      color: AppColors.danger, fontSize: 12),
                )),
              ]),
            ),
        ],
      ],
    );
  }
}

// ── Wind angle detail ────────────────────────────────────────────────────────
class _WindAngleDetail extends StatelessWidget {
  final double? angle;
  final double? trueWind;
  final double? apparentWind;
  const _WindAngleDetail({this.angle, this.trueWind, this.apparentWind});

  String _pointOfSail(double a) {
    final abs = a.abs();
    if (abs < 30) return '迎风 (In Irons) — 无法航行';
    if (abs < 50) return '抢风 (Close Hauled)';
    if (abs < 70) return '近抢 (Close Reach)';
    if (abs < 110) return '横风 (Beam Reach)';
    if (abs < 150) return '宽帆 (Broad Reach)';
    return '顺风 (Running)';
  }

  @override
  Widget build(BuildContext context) {
    final isPort = (angle ?? 0) < 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (angle != null) ...[
          _detailRow('视风角', '${angle!.abs().toStringAsFixed(0)}°'),
          _detailRow('舷侧', isPort ? '左舷 (Port)' : '右舷 (Starboard)',
              valueColor: isPort ? AppColors.danger : AppColors.success),
          _detailRow('帆态', _pointOfSail(angle!)),
        ],
        if (trueWind != null)
          _detailRow('真风速', '${trueWind!.toStringAsFixed(1)} kn'),
        if (apparentWind != null)
          _detailRow('视风速', '${apparentWind!.toStringAsFixed(1)} kn'),
        if (angle != null && angle!.abs() < 30)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.warning.withAlpha(20),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.warning.withAlpha(80)),
            ),
            child: const Text('迎风区域 — 帆船无法正常驾帆，需机动',
                style: TextStyle(color: AppColors.warning, fontSize: 12)),
          ),
      ],
    );
  }
}

// ── Depth detail ─────────────────────────────────────────────────────────────
class _DepthDetail extends StatelessWidget {
  final double? depth;
  const _DepthDetail({this.depth});

  @override
  Widget build(BuildContext context) {
    Color color;
    String classification;
    if (depth == null) {
      color = AppColors.textMuted;
      classification = '无数据';
    } else if (depth! > 20) {
      color = AppColors.success;
      classification = '深水区 (>20m) — 安全';
    } else if (depth! > 5) {
      color = AppColors.success;
      classification = '正常水深 (5-20m)';
    } else if (depth! > 2) {
      color = AppColors.warning;
      classification = '注意 (2-5m) — 注意礁石';
    } else {
      color = AppColors.danger;
      classification = '浅水警告 (<2m) — 立即行动';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _detailRow('龙骨下水深', depth != null ? '${depth!.toStringAsFixed(2)} m' : '—',
            valueColor: color),
        _detailRow('水深分类', classification, valueColor: color),
        _detailRow('告警阈值', '< 2.0 m 触发浅水告警'),
        const Divider(color: AppColors.border, height: 24),
        const Text('水深参考',
            style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.0)),
        const SizedBox(height: 8),
        ...const [
          ('> 20m', '深水 — 大型船舶通航'),
          ('5–20m', '普通锚地 / 航道'),
          ('2–5m', '浅水 — 小型帆船注意'),
          ('< 2m', '危险浅水 — 立即转向'),
        ].map((r) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                SizedBox(width: 80,
                    child: Text(r.$1,
                        style: const TextStyle(
                            color: AppColors.cyan, fontSize: 12))),
                Expanded(child: Text(r.$2,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12))),
              ]),
            )),
      ],
    );
  }
}

// ── Battery detail ───────────────────────────────────────────────────────────
class _BatteryDetail extends ConsumerWidget {
  final String batteryId;
  final BatteryState battery;
  const _BatteryDetail({required this.batteryId, required this.battery});

  String _chargeState(BatteryState b) {
    final c = b.current;
    if (c == null) return '—';
    if (c > 0.5) return '充电中 ↑';
    if (c < -0.5) return '放电中 ↓';
    return '浮充 ≈';
  }

  Color _chargeColor(BatteryState b) {
    final c = b.current;
    if (c == null) return AppColors.textMuted;
    if (c > 0.5) return AppColors.success;
    if (c < -0.5) return AppColors.warning;
    return AppColors.cyan;
  }

  String _timeRemaining(BatteryState b) {
    final soc = b.stateOfCharge;
    final c = b.current;
    if (soc == null || c == null || c >= 0) return '—';
    // Assume 100Ah battery if capacity unknown
    const capacityAh = 100.0;
    final remainingAh = soc * capacityAh;
    final hours = remainingAh / c.abs();
    if (hours > 99) return '> 99h';
    if (hours >= 1) return '${hours.toStringAsFixed(1)} h';
    return '${(hours * 60).toStringAsFixed(0)} min';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(powerHistoryProvider);
    final battSamples = history.batteryHistory[batteryId] ?? [];
    final voltages = battSamples
        .where((s) => s.voltage != null)
        .map((s) => s.voltage!)
        .toList();
    final currents = battSamples
        .where((s) => s.current != null)
        .map((s) => s.current!)
        .toList();
    final socs = battSamples
        .where((s) => s.soc != null)
        .map((s) => s.soc! * 100)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _detailRow('电压', battery.voltage != null
            ? '${battery.voltage!.toStringAsFixed(2)} V' : '—'),
        _detailRow('电流', battery.current != null
            ? '${battery.current!.toStringAsFixed(1)} A' : '—'),
        _detailRow('荷电状态 (SOC)', battery.stateOfCharge != null
            ? '${(battery.stateOfCharge! * 100).toStringAsFixed(0)}%' : '—'),
        _detailRow('充电状态', _chargeState(battery),
            valueColor: _chargeColor(battery)),
        _detailRow('预计剩余时间', _timeRemaining(battery)),
        const Divider(color: AppColors.border, height: 24),
        const Text('电压趋势 (1h)',
            style: TextStyle(
                color: AppColors.textMuted, fontSize: 11,
                fontWeight: FontWeight.w600, letterSpacing: 1.0)),
        const SizedBox(height: 8),
        SparklineChart(values: voltages, color: AppColors.cyan, height: 70),
        const SizedBox(height: 16),
        const Text('电流趋势 (1h)',
            style: TextStyle(
                color: AppColors.textMuted, fontSize: 11,
                fontWeight: FontWeight.w600, letterSpacing: 1.0)),
        const SizedBox(height: 8),
        SparklineChart(values: currents, color: AppColors.teal, height: 70),
        if (socs.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('SOC 趋势 (1h)',
              style: TextStyle(
                  color: AppColors.textMuted, fontSize: 11,
                  fontWeight: FontWeight.w600, letterSpacing: 1.0)),
          const SizedBox(height: 8),
          SparklineChart(values: socs, color: AppColors.success,
              minY: 0, maxY: 100, height: 70),
        ],
      ],
    );
  }
}
