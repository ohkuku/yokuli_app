import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/models/alarm.dart';
import '../../../core/models/alarm_rule.dart';
import '../../../core/providers/alarm_provider.dart';
import '../../../core/providers/alarm_rule_provider.dart';
import '../../../core/theme/app_colors.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _typeLabel(AlarmType type) {
  switch (type) {
    case AlarmType.battery:
      return '电池低压';
    case AlarmType.depth:
      return '水深告警';
    case AlarmType.speed:
      return '航速告警';
    case AlarmType.mob:
      return 'MOB落水告警';
    case AlarmType.ais:
      return 'AIS碰撞风险';
    case AlarmType.solar:
      return '太阳能告警';
    case AlarmType.connection:
      return '连接告警';
  }
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

IconData _typeIcon(AlarmType type) {
  switch (type) {
    case AlarmType.battery:
      return Icons.battery_alert_rounded;
    case AlarmType.depth:
      return Icons.waves_rounded;
    case AlarmType.speed:
      return Icons.speed_rounded;
    case AlarmType.mob:
      return Icons.person_off_rounded;
    case AlarmType.ais:
      return Icons.radar_rounded;
    case AlarmType.solar:
      return Icons.wb_sunny_rounded;
    case AlarmType.connection:
      return Icons.link_off_rounded;
  }
}

String _timeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inSeconds < 60) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
  if (diff.inHours < 24) return '${diff.inHours} 小时前';
  return DateFormat('MM-dd HH:mm').format(dt);
}

// ---------------------------------------------------------------------------
// NotificationsScreen
// ---------------------------------------------------------------------------

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alarms = ref.watch(alarmProvider).where((a) => !a.deleted).toList();
    final activeCount = alarms
        .where((a) =>
            a.status == AlarmStatus.active || a.status == AlarmStatus.snoozed)
        .length;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textPrimary,
          title: Row(
            children: [
              const Text('通知中心',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700)),
              if (activeCount > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.danger,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$activeCount',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ],
          ),
          bottom: TabBar(
            labelColor: AppColors.cyan,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.cyan,
            tabs: [
              Tab(text: '当前告警 ($activeCount)'),
              const Tab(text: '历史记录'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _ActiveTab(alarms: alarms),
            _HistoryTab(alarms: alarms),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Active Tab
// ---------------------------------------------------------------------------

class _ActiveTab extends ConsumerWidget {
  final List<Alarm> alarms;
  const _ActiveTab({required this.alarms});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = alarms
        .where((a) =>
            a.status == AlarmStatus.active || a.status == AlarmStatus.snoozed)
        .toList()
      ..sort((a, b) => b.triggeredAt.compareTo(a.triggeredAt));

    if (active.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded,
                size: 64, color: AppColors.success.withOpacity(0.7)),
            const SizedBox(height: 16),
            const Text('一切正常',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 18,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: active.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) => _AlarmCard(alarm: active[i]),
    );
  }
}

// ---------------------------------------------------------------------------
// History Tab
// ---------------------------------------------------------------------------

class _HistoryTab extends StatelessWidget {
  final List<Alarm> alarms;
  const _HistoryTab({required this.alarms});

  @override
  Widget build(BuildContext context) {
    final history = alarms
        .where((a) =>
            a.status == AlarmStatus.acknowledged ||
            a.status == AlarmStatus.cleared)
        .toList()
      ..sort((a, b) => b.triggeredAt.compareTo(a.triggeredAt));

    if (history.isEmpty) {
      return const Center(
        child: Text('暂无历史记录',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: history.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, i) => _HistoryRow(alarm: history[i]),
    );
  }
}

// ---------------------------------------------------------------------------
// AlarmCard (active/snoozed)
// ---------------------------------------------------------------------------

class _AlarmCard extends ConsumerWidget {
  final Alarm alarm;
  const _AlarmCard({required this.alarm});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = _levelColor(alarm.level);
    final rules = ref.watch(alarmRuleProvider);
    final rule = rules[alarm.type];
    final snoozeMins = rule?.snoozeMins ?? 15;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: color, width: 4),
          top: BorderSide(color: AppColors.border, width: 0.5),
          right: BorderSide(color: AppColors.border, width: 0.5),
          bottom: BorderSide(color: AppColors.border, width: 0.5),
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row
          Row(
            children: [
              Icon(_typeIcon(alarm.type), size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _typeLabel(alarm.type),
                  style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                _timeAgo(alarm.triggeredAt),
                style: const TextStyle(
                    color: AppColors.textMuted, fontSize: 11),
              ),
              if (alarm.isSnoozed && alarm.snoozedUntil != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: AppColors.warning.withOpacity(0.4)),
                  ),
                  child: Text(
                    '⏰ ${alarm.snoozedUntil!.difference(DateTime.now()).inMinutes + 1}min',
                    style: const TextStyle(
                        color: AppColors.warning,
                        fontSize: 10,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ],
          ),
          if (alarm.message != null) ...[
            const SizedBox(height: 6),
            Text(
              alarm.message!,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
          const SizedBox(height: 10),
          // Action buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (snoozeMins > 0) _SnoozeButton(alarm: alarm),
              const SizedBox(width: 8),
              if (alarm.status == AlarmStatus.active)
                _ActionButton(
                  label: '确认',
                  color: AppColors.cyan,
                  onTap: () =>
                      ref.read(alarmProvider.notifier).acknowledge(alarm.id),
                ),
              const SizedBox(width: 8),
              _ActionButton(
                label: '清除',
                color: AppColors.textSecondary,
                onTap: () =>
                    ref.read(alarmProvider.notifier).clear(alarm.id),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Snooze dropdown button
// ---------------------------------------------------------------------------

class _SnoozeButton extends ConsumerWidget {
  final Alarm alarm;
  const _SnoozeButton({required this.alarm});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<int>(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.warning.withOpacity(0.12),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: AppColors.warning.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.snooze_rounded, size: 14, color: AppColors.warning),
            SizedBox(width: 4),
            Text('暂停',
                style: TextStyle(
                    color: AppColors.warning,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            SizedBox(width: 2),
            Icon(Icons.arrow_drop_down_rounded,
                size: 16, color: AppColors.warning),
          ],
        ),
      ),
      itemBuilder: (_) => [5, 15, 30, 60]
          .map((m) => PopupMenuItem<int>(
                value: m,
                child: Text('$m 分钟',
                    style: const TextStyle(color: AppColors.textPrimary)),
              ))
          .toList(),
      onSelected: (mins) =>
          ref.read(alarmProvider.notifier).snooze(alarm.id, mins),
    );
  }
}

// ---------------------------------------------------------------------------
// Generic action button
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
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Text(
          label,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// History row (no action buttons)
// ---------------------------------------------------------------------------

class _HistoryRow extends StatelessWidget {
  final Alarm alarm;
  const _HistoryRow({required this.alarm});

  @override
  Widget build(BuildContext context) {
    final color = _levelColor(alarm.level);
    final statusLabel = alarm.status == AlarmStatus.acknowledged ? '已确认' : '已清除';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_typeLabel(alarm.type),
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                if (alarm.message != null)
                  Text(alarm.message!,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_timeAgo(alarm.triggeredAt),
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 11)),
              const SizedBox(height: 2),
              Text(statusLabel,
                  style: const TextStyle(
                      color: AppColors.textDim,
                      fontSize: 11,
                      fontWeight: FontWeight.w500)),
            ],
          ),
        ],
      ),
    );
  }
}
