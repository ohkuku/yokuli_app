import 'alarm_rule.dart';

// Sentinel for nullable copyWith
const Object _instanceSentinel = Object();

enum AlarmInstanceStatus { active, acknowledged, snoozed, cleared }

class AlarmInstance {
  final String id;
  final String ruleId;

  /// Snapshot of the rule name at trigger time.
  final String ruleName;

  final AlarmLevel level;
  final AlarmInstanceStatus status;
  final DateTime triggeredAt;

  /// Set when status == snoozed.
  final DateTime? snoozedUntil;

  /// Set when the instance transitions to cleared (manually or by auto-clear).
  final DateTime? clearedAt;

  /// The sensor value that caused the alarm to trigger, for display purposes.
  final double? triggeredValue;

  /// Human-readable description of the alarm condition.
  final String message;

  // Sync envelope — JSON keys match sync engine expectations.
  final DateTime updatedAt;
  final bool deleted;

  /// Always 'global'.
  final String scope;
  final String sourceDeviceId;

  /// Always 1.
  final int schemaVersion;

  const AlarmInstance({
    required this.id,
    required this.ruleId,
    required this.ruleName,
    required this.level,
    required this.status,
    required this.triggeredAt,
    this.snoozedUntil,
    this.clearedAt,
    this.triggeredValue,
    required this.message,
    required this.updatedAt,
    this.deleted = false,
    this.scope = 'global',
    required this.sourceDeviceId,
    this.schemaVersion = 1,
  });

  AlarmInstance copyWith({
    String? id,
    String? ruleId,
    String? ruleName,
    AlarmLevel? level,
    AlarmInstanceStatus? status,
    DateTime? triggeredAt,
    Object? snoozedUntil = _instanceSentinel,
    Object? clearedAt = _instanceSentinel,
    Object? triggeredValue = _instanceSentinel,
    String? message,
    DateTime? updatedAt,
    bool? deleted,
    String? scope,
    String? sourceDeviceId,
    int? schemaVersion,
  }) {
    return AlarmInstance(
      id: id ?? this.id,
      ruleId: ruleId ?? this.ruleId,
      ruleName: ruleName ?? this.ruleName,
      level: level ?? this.level,
      status: status ?? this.status,
      triggeredAt: triggeredAt ?? this.triggeredAt,
      snoozedUntil: snoozedUntil == _instanceSentinel
          ? this.snoozedUntil
          : snoozedUntil as DateTime?,
      clearedAt: clearedAt == _instanceSentinel
          ? this.clearedAt
          : clearedAt as DateTime?,
      triggeredValue: triggeredValue == _instanceSentinel
          ? this.triggeredValue
          : triggeredValue as double?,
      message: message ?? this.message,
      updatedAt: updatedAt ?? this.updatedAt,
      deleted: deleted ?? this.deleted,
      scope: scope ?? this.scope,
      sourceDeviceId: sourceDeviceId ?? this.sourceDeviceId,
      schemaVersion: schemaVersion ?? this.schemaVersion,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'ruleId': ruleId,
        'ruleName': ruleName,
        'lv': level.index,
        'st': status.index,
        'ta': triggeredAt.toIso8601String(),
        if (snoozedUntil != null) 'su': snoozedUntil!.toIso8601String(),
        if (clearedAt != null) 'clAt': clearedAt!.toIso8601String(),
        if (triggeredValue != null) 'tv': triggeredValue,
        'msg': message,
        'ua': updatedAt.toIso8601String(),
        if (deleted) 'del': true,
        'scope': scope,
        'src': sourceDeviceId,
        'sv': schemaVersion,
      };

  factory AlarmInstance.fromJson(Map<String, dynamic> json) {
    final triggeredAt = DateTime.parse(json['ta'] as String);
    return AlarmInstance(
      id: json['id'] as String,
      ruleId: json['ruleId'] as String,
      ruleName: json['ruleName'] as String? ?? '',
      level: AlarmLevel.values[json['lv'] as int? ?? AlarmLevel.warning.index],
      status: AlarmInstanceStatus
          .values[json['st'] as int? ?? AlarmInstanceStatus.active.index],
      triggeredAt: triggeredAt,
      snoozedUntil: json['su'] != null
          ? DateTime.parse(json['su'] as String)
          : null,
      clearedAt: json['clAt'] != null
          ? DateTime.parse(json['clAt'] as String)
          : null,
      triggeredValue: json['tv'] != null ? (json['tv'] as num).toDouble() : null,
      message: json['msg'] as String? ?? '',
      updatedAt: json['ua'] != null
          ? DateTime.parse(json['ua'] as String)
          : triggeredAt,
      deleted: json['del'] as bool? ?? false,
      scope: json['scope'] as String? ?? 'global',
      sourceDeviceId: json['src'] as String? ?? '',
      schemaVersion: json['sv'] as int? ?? 1,
    );
  }
}
