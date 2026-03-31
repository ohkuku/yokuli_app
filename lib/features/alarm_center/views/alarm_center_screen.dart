import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/alarm_action.dart';
import '../../../core/models/alarm_instance.dart';
import '../../../core/models/alarm_rule.dart';
import '../../../core/providers/alarm_action_provider.dart';
import '../../../core/providers/alarm_instance_provider.dart';
import '../../../core/providers/alarm_rule_provider.dart';
import '../../../core/providers/device_provider.dart';
import '../../../core/providers/locale_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/theme/app_colors.dart';
import 'alarm_rule_edit_screen.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _timeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m前';
  if (diff.inHours < 24) return '${diff.inHours}h前';
  return '${dt.month}月${dt.day}日';
}

Color _levelColor(AlarmLevel level) {
  switch (level) {
    case AlarmLevel.critical:
      return AppColors.danger;
    case AlarmLevel.warning:
      return AppColors.warning;
    case AlarmLevel.info:
      return AppColors.cyan;
  }
}

String _metricDisplayName(String metric) {
  const names = {
    'sog': '航速',
    'depth_keel': '龙骨水深',
    'depth_surface': '水面水深',
    'battery_voltage_main': '主电池电压',
    'wind_true_speed': '真风速',
    'wind_apparent_speed': '表观风速',
    'solar_power_total': '太阳能总功率',
  };
  return names[metric] ?? metric;
}

String _operatorSymbol(AlarmOperator op) {
  switch (op) {
    case AlarmOperator.greaterEqual:
      return '≥';
    case AlarmOperator.lessEqual:
      return '≤';
    case AlarmOperator.greaterThan:
      return '>';
    case AlarmOperator.lessThan:
      return '<';
  }
}

String _conditionSummary(AlarmCondition cond) {
  final name = _metricDisplayName(cond.metric);
  final sym = _operatorSymbol(cond.operator);
  final unit = vesselMetrics[cond.metric]?.$2 ?? '';
  return '$name $sym ${cond.threshold} $unit';
}

String _actionLabel(AlarmActionType type) {
  switch (type) {
    case AlarmActionType.acknowledged:
      return '已确认';
    case AlarmActionType.snoozed:
      return '已暂停';
    case AlarmActionType.cleared:
      return '已清除';
  }
}

// ---------------------------------------------------------------------------
// AlarmCenterScreen
// ---------------------------------------------------------------------------

class AlarmCenterScreen extends ConsumerStatefulWidget {
  const AlarmCenterScreen({super.key});

  @override
  ConsumerState<AlarmCenterScreen> createState() => _AlarmCenterScreenState();
}

class _AlarmCenterScreenState extends ConsumerState<AlarmCenterScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(stringsProvider); // locale refresh
    final activeCount = ref.watch(alarmInstanceCountProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        title: Row(
          children: [
            const Text(
              '告警中心',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (activeCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.danger,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$activeCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.cyan,
          labelColor: AppColors.cyan,
          unselectedLabelColor: AppColors.textMuted,
          labelStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
          tabs: const [
            Tab(text: '活动告警'),
            Tab(text: '告警规则'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _ActiveAlarmsTab(),
          _AlarmRulesTab(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 1 — Active Alarms
// ---------------------------------------------------------------------------

class _ActiveAlarmsTab extends ConsumerWidget {
  const _ActiveAlarmsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final instances = ref.watch(activeAlarmInstancesProvider);

    if (instances.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_off_rounded,
              size: 56,
              color: AppColors.inactive,
            ),
            SizedBox(height: 16),
            Text(
              '暂无活动告警',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 6),
            Text(
              '一切正常',
              style: TextStyle(
                color: AppColors.textDim,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      itemCount: instances.length,
      itemBuilder: (context, index) {
        return _AlarmInstanceCard(instance: instances[index]);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Alarm Instance Card
// ---------------------------------------------------------------------------

class _AlarmInstanceCard extends ConsumerWidget {
  final AlarmInstance instance;
  const _AlarmInstanceCard({required this.instance});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final levelColor = _levelColor(instance.level);
    final isSnoozed = instance.status == AlarmInstanceStatus.snoozed;
    final isActive = instance.status == AlarmInstanceStatus.active;

    // Find the matching rule to get snoozeMins
    final rules = ref.watch(alarmRuleProvider);
    final matchingRule = rules.cast<AlarmRule?>().firstWhere(
          (r) => r?.id == instance.ruleId,
          orElse: () => null,
        );
    final snoozeMins = matchingRule?.snoozeMins ?? 0;
    final canSnooze = instance.level != AlarmLevel.critical && snoozeMins > 0;

    // Snooze countdown
    String? snoozeLabel;
    if (isSnoozed && instance.snoozedUntil != null) {
      final remaining = instance.snoozedUntil!.difference(DateTime.now());
      if (remaining.isNegative) {
        snoozeLabel = '已暂停 · 即将恢复';
      } else {
        snoozeLabel = '已暂停 · 剩余${remaining.inMinutes}m';
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => _showDetailSheet(context, ref, instance),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Colored left border
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: levelColor,
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(12),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header row: name + badge + time
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                instance.ruleName,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _LevelBadge(level: instance.level),
                            const SizedBox(width: 8),
                            Text(
                              _timeAgo(instance.triggeredAt),
                              style: const TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        // Message
                        Text(
                          instance.message,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        // Snooze status
                        if (snoozeLabel != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(
                                Icons.snooze_rounded,
                                size: 12,
                                color: AppColors.warning,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                snoozeLabel,
                                style: const TextStyle(
                                  color: AppColors.warning,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 10),
                        // Action row
                        Row(
                          children: [
                            if (isActive) ...[
                              _ActionButton(
                                label: '确认',
                                color: AppColors.teal,
                                onTap: () => _acknowledge(context, ref),
                              ),
                              const SizedBox(width: 8),
                            ],
                            if (canSnooze && !isSnoozed) ...[
                              _ActionButton(
                                label: '暂停',
                                color: AppColors.warning,
                                onTap: () =>
                                    _showSnoozeDialog(context, ref, snoozeMins),
                              ),
                              const SizedBox(width: 8),
                            ],
                            _ActionButton(
                              label: '清除',
                              color: AppColors.danger,
                              onTap: () => _clear(context, ref),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _acknowledge(BuildContext context, WidgetRef ref) {
    final device = ref.read(deviceProvider);
    final settings = ref.read(settingsProvider);
    ref.read(alarmInstanceProvider.notifier).acknowledge(
          instance.id,
          deviceId: device.deviceId,
          deviceName: settings.deviceName,
        );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('告警已确认')),
    );
  }

  void _showSnoozeDialog(
      BuildContext context, WidgetRef ref, int maxMins) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _SnoozeSheet(
        onSnooze: (minutes) {
          Navigator.pop(ctx);
          final device = ref.read(deviceProvider);
          final settings = ref.read(settingsProvider);
          ref.read(alarmInstanceProvider.notifier).snooze(
                instance.id,
                minutes,
                deviceId: device.deviceId,
                deviceName: settings.deviceName,
              );
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('告警已暂停 $minutes 分钟')),
          );
        },
      ),
    );
  }

  void _clear(BuildContext context, WidgetRef ref) {
    final device = ref.read(deviceProvider);
    final settings = ref.read(settingsProvider);
    ref.read(alarmInstanceProvider.notifier).clear(
          instance.id,
          deviceId: device.deviceId,
          deviceName: settings.deviceName,
        );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('告警已清除')),
    );
  }

  void _showDetailSheet(
      BuildContext context, WidgetRef ref, AlarmInstance inst) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AlarmDetailSheet(instance: inst),
    );
  }
}

// ---------------------------------------------------------------------------
// Level Badge
// ---------------------------------------------------------------------------

class _LevelBadge extends StatelessWidget {
  final AlarmLevel level;
  const _LevelBadge({required this.level});

  @override
  Widget build(BuildContext context) {
    final color = _levelColor(level);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(
        level.displayName,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Action Button
// ---------------------------------------------------------------------------

class _ActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: color.withAlpha(25),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: color.withAlpha(80)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Snooze Sheet
// ---------------------------------------------------------------------------

class _SnoozeSheet extends StatelessWidget {
  final void Function(int minutes) onSnooze;
  const _SnoozeSheet({required this.onSnooze});

  @override
  Widget build(BuildContext context) {
    const options = [5, 15, 30, 60];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Row(
            children: [
              Icon(Icons.snooze_rounded, size: 18, color: AppColors.warning),
              SizedBox(width: 8),
              Text(
                '选择暂停时长',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: options.map((mins) {
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: GestureDetector(
                    onTap: () => onSnooze(mins),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      alignment: Alignment.center,
                      child: Column(
                        children: [
                          Text(
                            '$mins',
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Text(
                            '分钟',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Alarm Detail Bottom Sheet
// ---------------------------------------------------------------------------

class _AlarmDetailSheet extends ConsumerWidget {
  final AlarmInstance instance;
  const _AlarmDetailSheet({required this.instance});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.watch(
        alarmActionsForInstanceProvider(instance.id));
    final levelColor = _levelColor(instance.level);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.cardBg,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Title row
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: levelColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      instance.ruleName,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _LevelBadge(level: instance.level),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(color: AppColors.divider, height: 1),
              const SizedBox(height: 14),
              // Details
              _DetailRow(label: '消息', value: instance.message),
              const SizedBox(height: 8),
              _DetailRow(
                  label: '触发时间',
                  value: _formatDt(instance.triggeredAt)),
              const SizedBox(height: 8),
              _DetailRow(
                  label: '状态',
                  value: _statusLabel(instance.status)),
              if (instance.triggeredValue != null) ...[
                const SizedBox(height: 8),
                _DetailRow(
                    label: '触发值',
                    value: instance.triggeredValue!.toStringAsFixed(2)),
              ],
              if (instance.snoozedUntil != null) ...[
                const SizedBox(height: 8),
                _DetailRow(
                    label: '暂停至',
                    value: _formatDt(instance.snoozedUntil!)),
              ],
              const SizedBox(height: 20),
              // Action history
              const Text(
                '操作记录',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 10),
              if (actions.isEmpty)
                const Text(
                  '暂无操作记录',
                  style: TextStyle(
                    color: AppColors.textDim,
                    fontSize: 12,
                  ),
                )
              else
                ...actions.reversed.map(
                  (a) => _ActionHistoryRow(action: a),
                ),
            ],
          ),
        );
      },
    );
  }

  String _formatDt(DateTime dt) {
    final mo = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$mo-$d $h:$m';
  }

  String _statusLabel(AlarmInstanceStatus status) {
    switch (status) {
      case AlarmInstanceStatus.active:
        return '活动';
      case AlarmInstanceStatus.acknowledged:
        return '已确认';
      case AlarmInstanceStatus.snoozed:
        return '已暂停';
      case AlarmInstanceStatus.cleared:
        return '已清除';
    }
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionHistoryRow extends StatelessWidget {
  final AlarmAction action;
  const _ActionHistoryRow({required this.action});

  @override
  Widget build(BuildContext context) {
    final mo = action.at.month.toString().padLeft(2, '0');
    final d = action.at.day.toString().padLeft(2, '0');
    final h = action.at.hour.toString().padLeft(2, '0');
    final m = action.at.minute.toString().padLeft(2, '0');

    String detail = _actionLabel(action.action);
    if (action.action == AlarmActionType.snoozed &&
        action.snoozeMinutes != null) {
      detail += ' ${action.snoozeMinutes}m';
    }
    if (action.note != null && action.note!.isNotEmpty) {
      detail += ' · ${action.note}';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: AppColors.inactive,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$mo-$d $h:$m',
            style: const TextStyle(
              color: AppColors.textDim,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              detail,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
          Text(
            action.deviceName.isNotEmpty ? action.deviceName : action.deviceId,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 2 — Alarm Rules
// ---------------------------------------------------------------------------

class _AlarmRulesTab extends ConsumerWidget {
  const _AlarmRulesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allRules =
        ref.watch(alarmRuleProvider).where((r) => !r.deleted).toList()
          ..sort((a, b) => a.name.compareTo(b.name));

    final enabled = allRules.where((r) => r.enabled).toList();
    final disabled = allRules.where((r) => !r.enabled).toList();
    final channelCfg = ref.watch(notifyChannelProvider);

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            // Active rules section
            if (enabled.isNotEmpty) ...[
              _SectionHeader(label: '活动规则'),
              const SizedBox(height: 8),
              _RuleGroup(rules: enabled),
              const SizedBox(height: 20),
            ],

            // Disabled rules section
            if (disabled.isNotEmpty) ...[
              _SectionHeader(label: '已禁用'),
              const SizedBox(height: 8),
              _RuleGroup(rules: disabled),
              const SizedBox(height: 20),
            ],

            if (allRules.isEmpty) ...[
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Text(
                    '暂无告警规则\n点击 + 创建新规则',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],

            // Notification channel settings
            _SectionHeader(label: '通知渠道'),
            const SizedBox(height: 8),
            _NotifyChannelCard(config: channelCfg),
            const SizedBox(height: 16),
          ],
        ),
        // FAB
        Positioned(
          right: 16,
          bottom: 24,
          child: FloatingActionButton(
            backgroundColor: AppColors.cyan,
            foregroundColor: AppColors.background,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AlarmRuleEditScreen(existing: null),
                ),
              );
            },
            child: const Icon(Icons.add_rounded),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Rule Group
// ---------------------------------------------------------------------------

class _RuleGroup extends ConsumerWidget {
  final List<AlarmRule> rules;
  const _RuleGroup({required this.rules});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        children: rules.asMap().entries.map((entry) {
          final idx = entry.key;
          final rule = entry.value;
          final isLast = idx == rules.length - 1;
          return Column(
            children: [
              if (rule.isBuiltIn)
                _RuleRow(rule: rule)
              else
                Dismissible(
                  key: ValueKey(rule.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withAlpha(30),
                      borderRadius: isLast
                          ? const BorderRadius.vertical(
                              bottom: Radius.circular(12))
                          : BorderRadius.zero,
                    ),
                    child: const Icon(
                      Icons.delete_rounded,
                      color: AppColors.danger,
                    ),
                  ),
                  confirmDismiss: (_) async {
                    return await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: AppColors.cardBg,
                            title: const Text(
                              '删除告警规则',
                              style: TextStyle(color: AppColors.textPrimary),
                            ),
                            content: Text(
                              '确定删除「${rule.name}」？',
                              style: const TextStyle(
                                  color: AppColors.textSecondary),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(ctx, false),
                                child: const Text(
                                  '取消',
                                  style: TextStyle(
                                      color: AppColors.textSecondary),
                                ),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.danger,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () =>
                                    Navigator.pop(ctx, true),
                                child: const Text('删除'),
                              ),
                            ],
                          ),
                        ) ??
                        false;
                  },
                  onDismissed: (_) {
                    ref
                        .read(alarmRuleProvider.notifier)
                        .delete(rule.id);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content:
                              Text('规则「${rule.name}」已删除')),
                    );
                  },
                  child: _RuleRow(rule: rule),
                ),
              if (!isLast)
                const Divider(
                    color: AppColors.divider, height: 1, indent: 16),
            ],
          );
        }).toList(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Rule Row
// ---------------------------------------------------------------------------

class _RuleRow extends ConsumerWidget {
  final AlarmRule rule;
  const _RuleRow({required this.rule});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final levelColor = _levelColor(rule.level);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AlarmRuleEditScreen(existing: rule),
          ),
        );
      },
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            // Level color dot
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: levelColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          rule.name,
                          style: TextStyle(
                            color: rule.enabled
                                ? AppColors.textPrimary
                                : AppColors.textMuted,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (rule.isBuiltIn) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.inactive.withAlpha(40),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: AppColors.inactive.withAlpha(80)),
                          ),
                          child: const Text(
                            '内置',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      _LevelBadge(level: rule.level),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _conditionSummary(rule.condition),
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Switch(
              value: rule.enabled,
              activeColor: AppColors.cyan,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (v) {
                ref.read(alarmRuleProvider.notifier).upsert(
                      rule.copyWith(
                        enabled: v,
                        updatedAt: DateTime.now(),
                      ),
                    );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Notify Channel Card
// ---------------------------------------------------------------------------

class _NotifyChannelCard extends ConsumerStatefulWidget {
  final NotifyChannelConfig config;
  const _NotifyChannelCard({required this.config});

  @override
  ConsumerState<_NotifyChannelCard> createState() =>
      _NotifyChannelCardState();
}

class _NotifyChannelCardState extends ConsumerState<_NotifyChannelCard> {
  late final TextEditingController _webhookCtrl;

  @override
  void initState() {
    super.initState();
    _webhookCtrl =
        TextEditingController(text: widget.config.discordWebhookUrl);
  }

  @override
  void dispose() {
    _webhookCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(notifyChannelProvider);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Discord toggle
          SwitchListTile(
            title: const Text(
              'Discord Webhook',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            subtitle: const Text(
              '通过 Webhook 发送告警到 Discord',
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 12),
            ),
            value: config.discordEnabled,
            activeColor: AppColors.cyan,
            onChanged: (v) {
              ref
                  .read(notifyChannelProvider.notifier)
                  .update(config.copyWith(discordEnabled: v));
            },
          ),
          if (config.discordEnabled) ...[
            const Divider(
                height: 1, color: AppColors.divider, indent: 16),
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                controller: _webhookCtrl,
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Webhook URL',
                  labelStyle: const TextStyle(
                      color: AppColors.textSecondary),
                  filled: true,
                  fillColor: AppColors.surfaceElevated,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        const BorderSide(color: AppColors.cyan),
                  ),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.check_rounded,
                        color: AppColors.teal),
                    onPressed: _saveWebhookUrl,
                  ),
                ),
                onSubmitted: (_) => _saveWebhookUrl(),
              ),
            ),
            const Divider(
                height: 1, color: AppColors.divider, indent: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  const Text(
                    '最低告警等级',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const Spacer(),
                  DropdownButton<AlarmLevel>(
                    value: config.discordMinLevel,
                    dropdownColor: AppColors.cardBg,
                    underline: const SizedBox.shrink(),
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 13),
                    items: AlarmLevel.values.map((lv) {
                      return DropdownMenuItem(
                        value: lv,
                        child: Text(lv.displayName),
                      );
                    }).toList(),
                    onChanged: (lv) {
                      if (lv != null) {
                        ref
                            .read(notifyChannelProvider.notifier)
                            .update(
                                config.copyWith(discordMinLevel: lv));
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _saveWebhookUrl() {
    final config = ref.read(notifyChannelProvider);
    ref.read(notifyChannelProvider.notifier).update(
          config.copyWith(
              discordWebhookUrl: _webhookCtrl.text.trim()),
        );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Webhook URL 已保存')),
    );
  }
}

// ---------------------------------------------------------------------------
// Section Header
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: AppColors.textMuted,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.5,
      ),
    );
  }
}
