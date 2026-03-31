import 'alarm_rule.dart';

enum AlarmActionType { acknowledged, snoozed, cleared }

class AlarmAction {
  final String id;
  final String instanceId;
  final AlarmActionType action;
  final String deviceId;

  /// Snapshot of device name at action time.
  final String deviceName;

  final DateTime at;
  final String? note;

  /// Only populated when action == snoozed.
  final int? snoozeMinutes;

  // Sync envelope
  final DateTime updatedAt;
  final bool deleted;

  /// Always 'global'.
  final String scope;
  final String sourceDeviceId;

  /// Always 1.
  final int schemaVersion;

  const AlarmAction({
    required this.id,
    required this.instanceId,
    required this.action,
    required this.deviceId,
    required this.deviceName,
    required this.at,
    this.note,
    this.snoozeMinutes,
    required this.updatedAt,
    this.deleted = false,
    this.scope = 'global',
    required this.sourceDeviceId,
    this.schemaVersion = 1,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'instId': instanceId,
        'act': action.index,
        'devId': deviceId,
        'devName': deviceName,
        'at': at.toIso8601String(),
        if (note != null) 'note': note,
        if (snoozeMinutes != null) 'snoozeMin': snoozeMinutes,
        'ua': updatedAt.toIso8601String(),
        if (deleted) 'del': true,
        'scope': scope,
        'src': sourceDeviceId,
        'sv': schemaVersion,
      };

  factory AlarmAction.fromJson(Map<String, dynamic> json) {
    final at = DateTime.parse(json['at'] as String);
    return AlarmAction(
      id: json['id'] as String,
      instanceId: json['instId'] as String,
      action: AlarmActionType.values[json['act'] as int],
      deviceId: json['devId'] as String? ?? '',
      deviceName: json['devName'] as String? ?? '',
      at: at,
      note: json['note'] as String?,
      snoozeMinutes: json['snoozeMin'] as int?,
      updatedAt: json['ua'] != null
          ? DateTime.parse(json['ua'] as String)
          : at,
      deleted: json['del'] as bool? ?? false,
      scope: json['scope'] as String? ?? 'global',
      sourceDeviceId: json['src'] as String? ?? '',
      schemaVersion: json['sv'] as int? ?? 1,
    );
  }
}
