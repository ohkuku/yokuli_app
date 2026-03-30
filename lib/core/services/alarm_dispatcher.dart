import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../models/alarm.dart';
import '../models/alarm_rule.dart';
import '../providers/alarm_provider.dart';
import '../providers/alarm_rule_provider.dart';

// ---------------------------------------------------------------------------
// In-app banner provider
// ---------------------------------------------------------------------------

/// Watched by the root app widget to show an overlay banner for new alarms.
final inAppAlarmBannerProvider = StateProvider<Alarm?>((ref) => null);

// ---------------------------------------------------------------------------
// AlarmDispatcher
// ---------------------------------------------------------------------------

class AlarmDispatcher {
  final Ref _ref;
  Timer? _snoozeTimer;

  AlarmDispatcher(this._ref) {
    _ref.listen<List<Alarm>>(alarmProvider, (prev, next) {
      if (prev == null) return;
      final prevIds = {for (final a in prev) a.id};
      for (final alarm in next) {
        if (!prevIds.contains(alarm.id) && alarm.status == AlarmStatus.active) {
          _dispatch(alarm);
        }
      }
    });

    // Check snoozed alarms every 30 seconds.
    _snoozeTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _checkSnoozed());
  }

  void _dispatch(Alarm alarm) {
    final rules = _ref.read(alarmRuleProvider);
    final rule = rules[alarm.type];
    if (rule == null || !rule.enabled) return;

    for (final ch in rule.channels) {
      switch (ch) {
        case NotifyChannel.inApp:
          _showInAppBanner(alarm);
        case NotifyChannel.sound:
          _playSound();
        case NotifyChannel.discord:
          _sendDiscord(alarm);
      }
    }
  }

  void _showInAppBanner(Alarm alarm) {
    _ref.read(inAppAlarmBannerProvider.notifier).state = alarm;
    // Auto-dismiss after 8 seconds.
    Future.delayed(const Duration(seconds: 8), () {
      if (_ref.read(inAppAlarmBannerProvider)?.id == alarm.id) {
        _ref.read(inAppAlarmBannerProvider.notifier).state = null;
      }
    });
  }

  void _playSound() {
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.alert);
  }

  Future<void> _sendDiscord(Alarm alarm) async {
    final cfg = _ref.read(notifyChannelProvider);
    if (!cfg.discordEnabled || cfg.discordWebhookUrl.isEmpty) return;
    // Only fire discord for alarms at or above the configured minimum level.
    if (alarm.level.index > cfg.discordMinLevel.index) return;
    try {
      final client = http.Client();
      await client.post(
        Uri.parse(cfg.discordWebhookUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'content':
              '🚨 **[${alarm.level.name.toUpperCase()}]** ${alarm.type.name}: ${alarm.message ?? ""}',
        }),
      );
    } catch (_) {}
  }

  void _checkSnoozed() {
    final now = DateTime.now();
    for (final alarm in _ref.read(alarmProvider)) {
      if (alarm.status == AlarmStatus.snoozed &&
          alarm.snoozedUntil != null &&
          now.isAfter(alarm.snoozedUntil!)) {
        _ref.read(alarmProvider.notifier).reactivate(alarm.id);
        final reactivated = _ref
            .read(alarmProvider)
            .firstWhere((a) => a.id == alarm.id, orElse: () => alarm);
        _dispatch(reactivated);
      }
    }
  }

  void dispose() => _snoozeTimer?.cancel();
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final alarmDispatcherProvider = Provider<AlarmDispatcher>((ref) {
  final d = AlarmDispatcher(ref);
  ref.onDispose(d.dispose);
  return d;
});
