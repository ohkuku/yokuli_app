import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/providers/notification_provider.dart';
import '../../../core/providers/device_provider.dart';
import '../../../core/providers/locale_provider.dart'; // ignore: unused_import
import '../../../core/models/notification_record.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Color _severityColor(NotificationSeverity severity) {
  switch (severity) {
    case NotificationSeverity.critical:
      return AppColors.danger;
    case NotificationSeverity.warning:
      return AppColors.warning;
    case NotificationSeverity.info:
      return AppColors.cyan;
  }
}

IconData _typeIcon(NotificationType type) {
  switch (type) {
    case NotificationType.alarm:
      return Icons.alarm_rounded;
    case NotificationType.mob:
      return Icons.directions_boat_rounded;
    case NotificationType.taskDue:
      return Icons.assignment_rounded;
    case NotificationType.system:
      return Icons.info_rounded;
  }
}

String _typeLabel(NotificationType type) {
  switch (type) {
    case NotificationType.alarm:
      return '告警';
    case NotificationType.mob:
      return 'MOB';
    case NotificationType.taskDue:
      return '任务';
    case NotificationType.system:
      return '系统';
  }
}

String _severityLabel(NotificationSeverity severity) {
  switch (severity) {
    case NotificationSeverity.critical:
      return '紧急';
    case NotificationSeverity.warning:
      return '警告';
    case NotificationSeverity.info:
      return '信息';
  }
}

/// Compact time-ago string matching the alarm center format:
/// 刚刚 / Xm前 / Xh前 / M月D日
String _timeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inSeconds < 60) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m前';
  if (diff.inHours < 24) return '${diff.inHours}h前';
  return '${dt.month}月${dt.day}日';
}

/// Full date-time for detail sheet: MM-DD HH:mm
String _formatDateTime(DateTime dt) {
  final mm = dt.month.toString().padLeft(2, '0');
  final dd = dt.day.toString().padLeft(2, '0');
  final hh = dt.hour.toString().padLeft(2, '0');
  final min = dt.minute.toString().padLeft(2, '0');
  return '$mm-$dd $hh:$min';
}

// ---------------------------------------------------------------------------
// NotificationsScreen
// ---------------------------------------------------------------------------

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationsProvider);
    final deviceId = ref.watch(deviceProvider).deviceId;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        title: const Text(
          '通知',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          if (unread.isNotEmpty)
            TextButton(
              onPressed: () => _markAllRead(ref, unread, deviceId),
              child: const Text(
                '全部已读',
                style: TextStyle(
                  color: AppColors.cyan,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
      body: unread.isEmpty ? _EmptyState() : _InboxList(notifications: unread),
    );
  }

  void _markAllRead(
    WidgetRef ref,
    List<NotificationRecord> unread,
    String deviceId,
  ) {
    for (final n in unread) {
      ref.read(notificationReceiptProvider.notifier).dismiss(
            n.id,
            deviceId: deviceId,
          );
    }
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inbox_rounded,
            size: 64,
            color: AppColors.textMuted.withOpacity(0.6),
          ),
          const SizedBox(height: 16),
          const Text(
            '没有新通知',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Inbox list
// ---------------------------------------------------------------------------

class _InboxList extends ConsumerWidget {
  final List<NotificationRecord> notifications;

  const _InboxList({required this.notifications});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceId = ref.watch(deviceProvider).deviceId;

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      itemCount: notifications.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final n = notifications[i];
        return _NotificationTile(
          notification: n,
          onDismiss: () => ref
              .read(notificationReceiptProvider.notifier)
              .dismiss(n.id, deviceId: deviceId),
          onTap: () => _showDetail(context, ref, n, deviceId),
        );
      },
    );
  }

  void _showDetail(
    BuildContext context,
    WidgetRef ref,
    NotificationRecord n,
    String deviceId,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.dialogBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _DetailSheet(
        notification: n,
        onDismiss: () {
          ref
              .read(notificationReceiptProvider.notifier)
              .dismiss(n.id, deviceId: deviceId);
          Navigator.of(context).pop();
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Notification tile with swipe-to-dismiss
// ---------------------------------------------------------------------------

class _NotificationTile extends StatelessWidget {
  final NotificationRecord notification;
  final VoidCallback onDismiss;
  final VoidCallback onTap;

  const _NotificationTile({
    required this.notification,
    required this.onDismiss,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = _severityColor(notification.severity);

    return Dismissible(
      key: ValueKey(notification.id),
      direction: DismissDirection.startToEnd,
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: AppColors.success.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.check_circle_rounded,
                color: AppColors.success, size: 20),
            SizedBox(width: 8),
            Text(
              '已读',
              style: TextStyle(
                color: AppColors.success,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      onDismissed: (_) => onDismiss(),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(_typeIcon(notification.type),
                    size: 18, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notification.title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (notification.body.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        notification.body,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _timeAgo(notification.createdAt),
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Detail bottom sheet
// ---------------------------------------------------------------------------

class _DetailSheet extends StatelessWidget {
  final NotificationRecord notification;
  final VoidCallback onDismiss;

  const _DetailSheet({
    required this.notification,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final severityColor = _severityColor(notification.severity);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Badges row
            Row(
              children: [
                _Badge(
                  label: _typeLabel(notification.type),
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 8),
                _Badge(
                  label: _severityLabel(notification.severity),
                  color: severityColor,
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Title
            Text(
              notification.title,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (notification.body.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                notification.body,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
              ),
            ],
            const SizedBox(height: 12),
            // Created at
            Row(
              children: [
                const Icon(Icons.access_time_rounded,
                    size: 13, color: AppColors.textMuted),
                const SizedBox(width: 4),
                Text(
                  _formatDateTime(notification.createdAt),
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Action buttons
            if (notification.linkedEntityId != null) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    // Navigation to alarm center would be wired up at router level.
                    // For now, close the sheet — caller can hook routing as needed.
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.open_in_new_rounded,
                      size: 16, color: AppColors.cyan),
                  label: const Text(
                    '查看告警详情',
                    style: TextStyle(
                      color: AppColors.cyan,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.cyan, width: 1),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onDismiss,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.surface,
                  foregroundColor: AppColors.textPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  '关闭',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Badge chip
// ---------------------------------------------------------------------------

class _Badge extends StatelessWidget {
  final String label;
  final Color color;

  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.35)),
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
