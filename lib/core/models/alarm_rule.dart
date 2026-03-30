import 'alarm.dart';

enum NotifyChannel { inApp, sound, discord }

class AlarmRuleConfig {
  final AlarmType type;
  final bool enabled;
  final Set<NotifyChannel> channels;
  final int snoozeMins; // 0 = cannot snooze (e.g. MOB)

  const AlarmRuleConfig({
    required this.type,
    this.enabled = true,
    required this.channels,
    this.snoozeMins = 15,
  });

  AlarmRuleConfig copyWith({
    bool? enabled,
    Set<NotifyChannel>? channels,
    int? snoozeMins,
  }) {
    return AlarmRuleConfig(
      type: type,
      enabled: enabled ?? this.enabled,
      channels: channels ?? this.channels,
      snoozeMins: snoozeMins ?? this.snoozeMins,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'channels': channels.map((c) => c.index).toList(),
        'snoozeMins': snoozeMins,
      };

  factory AlarmRuleConfig.fromJson(AlarmType type, Map<String, dynamic> json) {
    final channelIndices = (json['channels'] as List?)?.cast<int>() ?? [];
    return AlarmRuleConfig(
      type: type,
      enabled: json['enabled'] as bool? ?? true,
      channels: channelIndices
          .map((i) => NotifyChannel.values[i])
          .toSet(),
      snoozeMins: json['snoozeMins'] as int? ?? 15,
    );
  }
}

class NotifyChannelConfig {
  final bool soundEnabled;
  final bool discordEnabled;
  final String discordWebhookUrl;
  final AlarmLevel discordMinLevel;

  const NotifyChannelConfig({
    this.soundEnabled = true,
    this.discordEnabled = false,
    this.discordWebhookUrl = '',
    this.discordMinLevel = AlarmLevel.critical,
  });

  NotifyChannelConfig copyWith({
    bool? soundEnabled,
    bool? discordEnabled,
    String? discordWebhookUrl,
    AlarmLevel? discordMinLevel,
  }) {
    return NotifyChannelConfig(
      soundEnabled: soundEnabled ?? this.soundEnabled,
      discordEnabled: discordEnabled ?? this.discordEnabled,
      discordWebhookUrl: discordWebhookUrl ?? this.discordWebhookUrl,
      discordMinLevel: discordMinLevel ?? this.discordMinLevel,
    );
  }

  Map<String, dynamic> toJson() => {
        'soundEnabled': soundEnabled,
        'discordEnabled': discordEnabled,
        'discordWebhookUrl': discordWebhookUrl,
        'discordMinLevel': discordMinLevel.index,
      };

  factory NotifyChannelConfig.fromJson(Map<String, dynamic> json) {
    return NotifyChannelConfig(
      soundEnabled: json['soundEnabled'] as bool? ?? true,
      discordEnabled: json['discordEnabled'] as bool? ?? false,
      discordWebhookUrl: json['discordWebhookUrl'] as String? ?? '',
      discordMinLevel: AlarmLevel
          .values[json['discordMinLevel'] as int? ?? AlarmLevel.critical.index],
    );
  }
}
