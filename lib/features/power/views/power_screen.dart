import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/providers/vessel_provider.dart';
import '../../../core/models/vessel_state.dart';

class PowerScreen extends ConsumerWidget {
  const PowerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final batteries = ref.watch(batteriesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Power')),
      body: SafeArea(
        child: batteries.isEmpty
            ? _EmptyPower()
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Summary row
                  _PowerSummaryRow(batteries: batteries),
                  const SizedBox(height: 16),

                  // Battery cards
                  const _SectionHeader('BATTERIES'),
                  const SizedBox(height: 8),
                  ...batteries.values.map((b) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _BatteryCard(battery: b),
                      )),
                ],
              ),
      ),
    );
  }
}

class _EmptyPower extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.battery_unknown_rounded, size: 64, color: AppColors.inactive),
          SizedBox(height: 16),
          Text('No power data',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
          SizedBox(height: 8),
          Text(
            'Connect to Signal K to receive\nbattery and power data.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _PowerSummaryRow extends StatelessWidget {
  final Map<String, BatteryState> batteries;

  const _PowerSummaryRow({required this.batteries});

  @override
  Widget build(BuildContext context) {
    final avgSoc = batteries.values
            .where((b) => b.stateOfCharge != null)
            .map((b) => b.stateOfCharge!)
            .fold(0.0, (a, b) => a + b) /
        (batteries.values.where((b) => b.stateOfCharge != null).length == 0
            ? 1
            : batteries.values.where((b) => b.stateOfCharge != null).length);

    final totalCurrent = batteries.values
        .where((b) => b.current != null)
        .fold(0.0, (sum, b) => sum + b.current!);

    return Row(
      children: [
        Expanded(
          child: _SummaryChip(
            icon: Icons.battery_charging_full_rounded,
            label: 'AVG SOC',
            value: batteries.values.any((b) => b.stateOfCharge != null)
                ? '${(avgSoc * 100).toStringAsFixed(0)}%'
                : '—',
            color: _socColor(avgSoc),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SummaryChip(
            icon: Icons.electrical_services_rounded,
            label: 'NET CURRENT',
            value: batteries.values.any((b) => b.current != null)
                ? '${totalCurrent.toStringAsFixed(1)} A'
                : '—',
            color: totalCurrent >= 0 ? AppColors.success : AppColors.warning,
          ),
        ),
      ],
    );
  }

  Color _socColor(double soc) {
    if (soc > 0.5) return AppColors.success;
    if (soc > 0.25) return AppColors.warning;
    return AppColors.danger;
  }
}

class _SummaryChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _SummaryChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0)),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: 20,
                  fontWeight: FontWeight.w300,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
      ]),
    );
  }
}

class _BatteryCard extends StatelessWidget {
  final BatteryState battery;

  const _BatteryCard({required this.battery});

  @override
  Widget build(BuildContext context) {
    final soc = battery.stateOfCharge ?? 0;
    final color = _socColor(soc);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.battery_charging_full_rounded, color: color, size: 20),
              const SizedBox(width: 8),
              Text(battery.name,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              if (battery.stateOfCharge != null)
                Text(
                  '${(soc * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                      color: color,
                      fontSize: 18,
                      fontWeight: FontWeight.w300,
                      fontFeatures: const [FontFeature.tabularFigures()]),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // SOC bar
          if (battery.stateOfCharge != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: soc,
                backgroundColor: AppColors.gaugeTrack,
                valueColor: AlwaysStoppedAnimation(color),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Stats row
          Row(
            children: [
              _Stat(label: 'VOLTAGE',
                  value: battery.voltage?.toStringAsFixed(2),
                  unit: 'V'),
              _Stat(label: 'CURRENT',
                  value: battery.current?.toStringAsFixed(1),
                  unit: 'A'),
              if (battery.temperature != null)
                _Stat(
                    label: 'TEMP',
                    value: battery.temperature?.toStringAsFixed(1),
                    unit: '°C'),
            ],
          ),
        ],
      ),
    );
  }

  Color _socColor(double soc) {
    if (soc > 0.5) return AppColors.success;
    if (soc > 0.25) return AppColors.warning;
    return AppColors.danger;
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String? value;
  final String unit;

  const _Stat({required this.label, this.value, required this.unit});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8)),
            Text(
              value != null ? '$value $unit' : '—',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      );
}

class _SectionHeader extends StatelessWidget {
  final String text;

  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
        ),
      );
}
