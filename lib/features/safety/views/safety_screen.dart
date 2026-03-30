import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/providers/vessel_provider.dart';
import '../../../core/providers/locale_provider.dart';
import '../../../core/l10n/strings.dart';
import '../providers/safety_provider.dart';

class SafetyScreen extends ConsumerStatefulWidget {
  const SafetyScreen({super.key});

  @override
  ConsumerState<SafetyScreen> createState() => _SafetyScreenState();
}

class _SafetyScreenState extends ConsumerState<SafetyScreen> {
  Timer? _elapsedTimer;
  int _elapsedSeconds = 0;

  @override
  void initState() {
    super.initState();
    // Wire up MOB alerts from LAN sync
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPendingMob();
    });
  }

  void _checkPendingMob() {
    final safety = ref.read(safetyProvider);
    if (safety.isMobActive) _startTimer();
  }

  void _startTimer() {
    _elapsedTimer?.cancel();
    final mob = ref.read(safetyProvider).activeMob;
    if (mob == null) return;
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _elapsedSeconds = mob.elapsed.inSeconds;
        });
      }
    });
  }

  void _stopTimer() {
    _elapsedTimer?.cancel();
    setState(() => _elapsedSeconds = 0);
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    super.dispose();
  }

  String _formatElapsed(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final safety = ref.watch(safetyProvider);
    final vessel = ref.watch(vesselProvider);

    if (safety.isMobActive) {
      final s = ref.watch(stringsProvider);
      return PopScope(
        canPop: false,
        child: _MobActiveScreen(
          s: s,
          safety: safety,
          vessel: vessel,
          elapsed: _formatElapsed(_elapsedSeconds),
          onCancel: () {
            ref.read(safetyProvider.notifier).cancelMob();
            _stopTimer();
          },
        ),
      );
    }

    final s = ref.watch(stringsProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(s.safetyTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // MOB trigger
            _MobTriggerCard(
              s: s,
              onTrigger: () {
                ref.read(safetyProvider.notifier).triggerMob();
                _startTimer();
              },
            ),
            const SizedBox(height: 24),

            // Depth alarm
            _SectionHeader(s.depthAlarmSection),
            const SizedBox(height: 8),
            _AlarmTile(
              icon: Icons.water_rounded,
              title: s.shallowWaterAlarm,
              subtitle: s.shallowWaterAlarmHint,
              enabled: safety.depthAlarmEnabled,
              triggered: safety.depthAlarmTriggered,
              threshold: safety.depthAlarmThreshold,
              unit: 'm',
              minThreshold: 0,
              maxThreshold: 20,
              onToggle: (v) => ref
                  .read(safetyProvider.notifier)
                  .setDepthAlarm(enabled: v),
              onThresholdChanged: (v) => ref
                  .read(safetyProvider.notifier)
                  .setDepthAlarm(
                      enabled: safety.depthAlarmEnabled, threshold: v),
            ),
            const SizedBox(height: 24),

            // Speed alarm
            _SectionHeader(s.speedAlarmSection),
            const SizedBox(height: 8),
            _AlarmTile(
              icon: Icons.speed_rounded,
              title: s.overSpeedAlarm,
              subtitle: s.overSpeedAlarmHint,
              enabled: safety.speedAlarmEnabled,
              triggered: safety.speedAlarmTriggered,
              threshold: safety.speedAlarmThreshold,
              unit: 'kn',
              minThreshold: 0,
              maxThreshold: 30,
              onToggle: (v) => ref
                  .read(safetyProvider.notifier)
                  .setSpeedAlarm(enabled: v),
              onThresholdChanged: (v) => ref
                  .read(safetyProvider.notifier)
                  .setSpeedAlarm(
                      enabled: safety.speedAlarmEnabled, threshold: v),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobActiveScreen extends StatelessWidget {
  final S s;
  final SafetyState safety;
  final vessel;
  final String elapsed;
  final VoidCallback onCancel;

  const _MobActiveScreen({
    required this.s,
    required this.safety,
    required this.vessel,
    required this.elapsed,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final mob = safety.activeMob!;
    final mobPos = mob.position;
    final currentPos = vessel.position;
    final distNm = (mobPos != null && currentPos != null)
        ? currentPos.distanceTo(mobPos)
        : null;
    final bearing = (mobPos != null && currentPos != null)
        ? currentPos.bearingTo(mobPos)
        : null;

    return Scaffold(
      backgroundColor: AppColors.danger.withAlpha(25),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // Alert banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.danger,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.person_off_rounded, size: 48, color: Colors.white),
                    const SizedBox(height: 8),
                    Text(s.manOverboard,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2)),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Elapsed time
              Text(
                elapsed,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 56,
                  fontWeight: FontWeight.w200,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                s.mobElapsed,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 20),

              // MOB position
              if (mobPos != null)
                _InfoRow(
                  icon: Icons.location_on_rounded,
                  label: s.mobPosition,
                  value:
                      '${mobPos.latitude.toStringAsFixed(5)}°, ${mobPos.longitude.toStringAsFixed(5)}°',
                ),

              if (distNm != null)
                _InfoRow(
                  icon: Icons.social_distance_rounded,
                  label: s.mobDistance,
                  value: '${distNm.toStringAsFixed(2)} nm',
                ),

              if (bearing != null)
                _InfoRow(
                  icon: Icons.navigation_rounded,
                  label: s.mobBearing,
                  value: '${bearing.toStringAsFixed(0)}°',
                ),

              const Spacer(),

              // Cancel button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _confirmCancel(context),
                  icon: const Icon(Icons.check_circle_outline_rounded,
                      color: AppColors.success),
                  label: Text(s.mobRecoveredBtn,
                      style: const TextStyle(color: AppColors.success)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.success),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmCancel(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.dialogBg,
        title: Text(s.cancelMobTitle),
        content: Text(s.cancelMobBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.back),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
            onPressed: () {
              Navigator.pop(context);
              onCancel();
            },
            child: Text(s.recovered),
          ),
        ],
      ),
    );
  }
}

class _MobTriggerCard extends StatelessWidget {
  final S s;
  final VoidCallback onTrigger;

  const _MobTriggerCard({required this.s, required this.onTrigger});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.danger.withAlpha(40), AppColors.cardBg],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.danger.withAlpha(80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.warning_rounded, color: AppColors.danger),
            const SizedBox(width: 8),
            Text(s.manOverboard,
                style: const TextStyle(
                    color: AppColors.danger,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1)),
          ]),
          const SizedBox(height: 8),
          Text(
            s.mobConfirmBody.split('\n\n').last,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _confirm(context),
              icon: const Icon(Icons.person_off_rounded),
              label: Text(s.triggerMob,
                  style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirm(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.dialogBg,
        title: Text('${s.manOverboard}?',
            style: const TextStyle(color: AppColors.danger)),
        content: Text(s.mobConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () {
              Navigator.pop(context);
              onTrigger();
            },
            child: Text(s.mobConfirm),
          ),
        ],
      ),
    );
  }
}

class _AlarmTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final bool triggered;
  final double threshold;
  final String unit;
  final double minThreshold;
  final double maxThreshold;
  final ValueChanged<bool> onToggle;
  final ValueChanged<double> onThresholdChanged;

  const _AlarmTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.triggered,
    required this.threshold,
    required this.unit,
    required this.minThreshold,
    required this.maxThreshold,
    required this.onToggle,
    required this.onThresholdChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: triggered
            ? AppColors.warning.withAlpha(25)
            : AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: triggered ? AppColors.warning : AppColors.border,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon,
                  color: triggered
                      ? AppColors.warning
                      : enabled
                          ? AppColors.cyan
                          : AppColors.inactive),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title),
                    Text(subtitle,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
              if (triggered)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.warning,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('⚠',
                      style: TextStyle(
                          color: Colors.black,
                          fontSize: 10,
                          fontWeight: FontWeight.w800)),
                ),
              Switch(value: enabled, onChanged: onToggle),
            ],
          ),
          if (enabled) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const SizedBox(width: 34),
                Expanded(
                  child: Slider(
                    value: threshold,
                    min: minThreshold,
                    max: maxThreshold,
                    onChanged: onThresholdChanged,
                    activeColor: AppColors.cyan,
                    inactiveColor: AppColors.gaugeTrack,
                  ),
                ),
                SizedBox(
                  width: 56,
                  child: Text(
                    '${threshold.toStringAsFixed(1)} $unit',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Text(label,
              style: const TextStyle(
                  color: AppColors.textMuted, fontSize: 11, letterSpacing: 0.5)),
          const Spacer(),
          Text(value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                fontFeatures: [FontFeature.tabularFigures()],
              )),
        ],
      ),
    );
  }
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
