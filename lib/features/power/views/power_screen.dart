import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/providers/power_provider.dart';
import '../../../core/providers/locale_provider.dart';
import '../../../core/models/vessel_state.dart';
import '../../../core/models/solar_state.dart';

class PowerScreen extends ConsumerWidget {
  const PowerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(s.power),
          bottom: TabBar(
            indicatorColor: AppColors.cyan,
            labelColor: AppColors.cyan,
            unselectedLabelColor: AppColors.textSecondary,
            tabs: [
              Tab(text: s.summary),
              Tab(text: s.batteries),
              Tab(text: s.solar),
            ],
          ),
        ),
        body: const SafeArea(
          child: TabBarView(
            children: [
              _SummaryTab(),
              _BatteriesTab(),
              _SolarTab(),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Summary Tab
// ─────────────────────────────────────────────────────────────────────────────

class _SummaryTab extends ConsumerWidget {
  const _SummaryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final power = ref.watch(powerProvider);
    final summary = power.summary;
    final hasData = summary.batteryVoltageMain != null ||
        summary.batterySocMain != null ||
        summary.batteryCurrentNet != null ||
        summary.solarInputPowerTotal != null;

    if (!hasData) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bolt_rounded, size: 64, color: AppColors.inactive),
            const SizedBox(height: 16),
            Text(
              s.waitingPowerData,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 16),
            ),
            const SizedBox(height: 8),
            const Text(
              'Connect to Signal K to receive\nbattery and power data.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _ChargeStatusCard(chargeState: summary.estimatedChargeState),
        const SizedBox(height: 16),
        _SummaryStatsGrid(summary: summary),
      ],
    );
  }
}

class _ChargeStatusCard extends StatelessWidget {
  final ChargeState chargeState;

  const _ChargeStatusCard({required this.chargeState});

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    final String label;
    final Color color;

    switch (chargeState) {
      case ChargeState.charging:
        icon = Icons.bolt_rounded;
        label = '充电中';
        color = AppColors.success;
      case ChargeState.discharging:
        icon = Icons.bolt_rounded;
        label = '放电中';
        color = AppColors.danger;
      case ChargeState.neutral:
      case ChargeState.unknown:
        icon = Icons.bolt_rounded;
        label = chargeState == ChargeState.neutral ? '空闲' : '未知';
        color = AppColors.inactive;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withAlpha(30),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '系统状态',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryStatsGrid extends StatelessWidget {
  final PowerSummaryState summary;

  const _SummaryStatsGrid({required this.summary});

  @override
  Widget build(BuildContext context) {
    final net = summary.batteryCurrentNet;
    final netColor = net == null
        ? AppColors.textPrimary
        : (net >= 0 ? AppColors.success : AppColors.danger);

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.7,
      children: [
        _StatCard(
          label: '主电压',
          value: summary.batteryVoltageMain?.toStringAsFixed(2),
          unit: 'V',
          color: AppColors.cyan,
        ),
        _StatCard(
          label: '净电流',
          value: net?.toStringAsFixed(1),
          unit: 'A',
          color: netColor,
        ),
        _StatCard(
          label: '主电量',
          value: summary.batterySocMain != null
              ? '${(summary.batterySocMain! * 100).toStringAsFixed(0)}'
              : null,
          unit: '%',
          color: _socColor(summary.batterySocMain ?? 0),
        ),
        _StatCard(
          label: '光伏输入',
          value: summary.solarInputPowerTotal?.toStringAsFixed(0),
          unit: 'W',
          color: AppColors.warning,
        ),
        _StatCard(
          label: '光伏充电',
          value: summary.solarChargeCurrentTotal?.toStringAsFixed(1),
          unit: 'A',
          color: AppColors.teal,
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

class _StatCard extends StatelessWidget {
  final String label;
  final String? value;
  final String unit;
  final Color color;

  const _StatCard({
    required this.label,
    this.value,
    required this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value != null ? '$value $unit' : '—',
            style: TextStyle(
              color: value != null ? color : AppColors.textMuted,
              fontSize: 20,
              fontWeight: FontWeight.w300,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Batteries Tab
// ─────────────────────────────────────────────────────────────────────────────

class _BatteriesTab extends ConsumerWidget {
  const _BatteriesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final batteries = ref.watch(powerProvider).batteries;

    if (batteries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.battery_unknown_rounded,
                size: 64, color: AppColors.inactive),
            const SizedBox(height: 16),
            Text(s.noBatteryData,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 16)),
            const SizedBox(height: 8),
            const Text(
              'Connect to Signal K to receive\nbattery data.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ...batteries.values.map((b) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _BatteryCard(battery: b),
            )),
      ],
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
              _Stat(
                  label: 'V',
                  value: battery.voltage?.toStringAsFixed(2),
                  unit: 'V'),
              _Stat(
                  label: 'A',
                  value: battery.current?.toStringAsFixed(1),
                  unit: 'A'),
              if (battery.temperature != null)
                _Stat(
                    label: '°C',
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

// ─────────────────────────────────────────────────────────────────────────────
// Solar Tab
// ─────────────────────────────────────────────────────────────────────────────

class _SolarTab extends ConsumerWidget {
  const _SolarTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final solar = ref.watch(powerProvider).solar;

    if (solar.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wb_sunny_rounded, size: 64, color: AppColors.inactive),
            const SizedBox(height: 16),
            Text(s.noSolarData,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 16)),
            const SizedBox(height: 8),
            const Text(
              'No solar charge controllers found.\nCheck your Signal K paths for\nelectrical.solar.* data.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ...solar.values.map((ctrl) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _SolarControllerCard(controller: ctrl),
            )),
      ],
    );
  }
}

class _SolarControllerCard extends StatelessWidget {
  final SolarChargeControllerState controller;

  const _SolarControllerCard({required this.controller});

  @override
  Widget build(BuildContext context) {
    final isStale = controller.status == SolarStatus.stale;

    return Stack(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row: id + status badge
              Row(
                children: [
                  const Icon(Icons.wb_sunny_rounded,
                      color: AppColors.warning, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      controller.id,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  _SolarStatusBadge(status: controller.status),
                ],
              ),
              const SizedBox(height: 12),

              // Stats grid row — only show output/charging values
              Row(
                children: [
                  _Stat(
                      label: 'PV 功率',
                      value: controller.effectiveInputPower?.toStringAsFixed(0),
                      unit: 'W'),
                  _Stat(
                      label: controller.inputVoltage != null ? 'PV V' : 'CHG V',
                      value: (controller.inputVoltage ?? controller.outputVoltage)?.toStringAsFixed(2),
                      unit: 'V'),
                  _Stat(
                      label: '充电 A',
                      value: controller.outputCurrent?.toStringAsFixed(1),
                      unit: 'A'),
                ],
              ),

              // Charger state chip
              if (controller.chargerState != SolarChargerState.unknown) ...[
                const SizedBox(height: 10),
                _ChargerStateChip(state: controller.chargerState),
              ],

              // Today's yield
              if (controller.yieldTodayWh != null) ...[
                const SizedBox(height: 10),
                Text(
                  '今日: ${controller.yieldTodayWh!.toStringAsFixed(1)} Wh',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),

        // Stale overlay
        if (isStale)
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: ColoredBox(
                color: AppColors.background.withAlpha(180),
                child: const Center(
                  child: Text(
                    '数据陈旧',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SolarStatusBadge extends StatelessWidget {
  final SolarStatus status;

  const _SolarStatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;

    switch (status) {
      case SolarStatus.charging:
        color = AppColors.success;
        label = '充电中';
      case SolarStatus.idle:
        color = AppColors.inactive;
        label = '空闲';
      case SolarStatus.fault:
        color = AppColors.danger;
        label = '故障';
      case SolarStatus.stale:
        color = AppColors.warning;
        label = '数据陈旧';
      case SolarStatus.noData:
        color = AppColors.inactive;
        label = '无数据';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ChargerStateChip extends StatelessWidget {
  final SolarChargerState state;

  const _ChargerStateChip({required this.state});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;

    switch (state) {
      case SolarChargerState.bulk:
        color = const Color(0xFF0A84FF);
        label = '大电流充电';
      case SolarChargerState.absorption:
        color = AppColors.cyan;
        label = '恒压充电';
      case SolarChargerState.float:
        color = AppColors.success;
        label = '浮充';
      case SolarChargerState.idle:
        color = AppColors.inactive;
        label = '空闲';
      case SolarChargerState.fault:
        color = AppColors.danger;
        label = '故障';
      case SolarChargerState.unknown:
        color = AppColors.inactive;
        label = '未知';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(70)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers
// ─────────────────────────────────────────────────────────────────────────────

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
