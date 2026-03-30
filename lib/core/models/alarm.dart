enum AlarmType { mob, depth, battery, solar, speed, connection, ais }

enum AlarmLevel { critical, warning, info }

enum AlarmStatus { active, acknowledged, cleared }

class Alarm {
  final String id;
  final AlarmType type;
  final AlarmLevel level;
  final AlarmStatus status;
  final DateTime triggeredAt;
  final String? acknowledgedBy;
  final DateTime? clearedAt;
  final String? linkedLogId;
  final String? message;

  const Alarm({
    required this.id,
    required this.type,
    required this.level,
    required this.status,
    required this.triggeredAt,
    this.acknowledgedBy,
    this.clearedAt,
    this.linkedLogId,
    this.message,
  });

  bool get isActive => status == AlarmStatus.active;

  Alarm copyWith({
    String? id,
    AlarmType? type,
    AlarmLevel? level,
    AlarmStatus? status,
    DateTime? triggeredAt,
    Object? acknowledgedBy = _sentinel,
    Object? clearedAt = _sentinel,
    Object? linkedLogId = _sentinel,
    Object? message = _sentinel,
  }) {
    return Alarm(
      id: id ?? this.id,
      type: type ?? this.type,
      level: level ?? this.level,
      status: status ?? this.status,
      triggeredAt: triggeredAt ?? this.triggeredAt,
      acknowledgedBy: acknowledgedBy == _sentinel
          ? this.acknowledgedBy
          : acknowledgedBy as String?,
      clearedAt:
          clearedAt == _sentinel ? this.clearedAt : clearedAt as DateTime?,
      linkedLogId: linkedLogId == _sentinel
          ? this.linkedLogId
          : linkedLogId as String?,
      message: message == _sentinel ? this.message : message as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'tp': type.index,
        'lv': level.index,
        's': status.index,
        'ta': triggeredAt.toIso8601String(),
        if (acknowledgedBy != null) 'ab': acknowledgedBy,
        if (clearedAt != null) 'ca': clearedAt!.toIso8601String(),
        if (linkedLogId != null) 'll': linkedLogId,
        if (message != null) 'msg': message,
      };

  factory Alarm.fromJson(Map<String, dynamic> json) {
    return Alarm(
      id: json['id'] as String,
      type: AlarmType.values[json['tp'] as int],
      level: AlarmLevel.values[json['lv'] as int],
      status: AlarmStatus.values[json['s'] as int],
      triggeredAt: DateTime.parse(json['ta'] as String),
      acknowledgedBy: json['ab'] as String?,
      clearedAt:
          json['ca'] != null ? DateTime.parse(json['ca'] as String) : null,
      linkedLogId: json['ll'] as String?,
      message: json['msg'] as String?,
    );
  }
}

// Sentinel object used for nullable copyWith pattern
const Object _sentinel = Object();
