enum AlarmType { mob, depth, battery, solar, speed, connection, ais }

enum AlarmLevel { critical, warning, info }

// Index-based serialisation — do NOT reorder existing values.
// snoozed is index 3 (after cleared=2).
enum AlarmStatus { active, acknowledged, cleared, snoozed }

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
  final DateTime? snoozedUntil;
  // LWW sync fields
  final DateTime updatedAt;
  final bool deleted;

  Alarm({
    required this.id,
    required this.type,
    required this.level,
    required this.status,
    required this.triggeredAt,
    this.acknowledgedBy,
    this.clearedAt,
    this.linkedLogId,
    this.message,
    this.snoozedUntil,
    DateTime? updatedAt,
    this.deleted = false,
  }) : updatedAt = updatedAt ?? triggeredAt;

  bool get isActive => status == AlarmStatus.active;
  bool get isSnoozed => status == AlarmStatus.snoozed;

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
    Object? snoozedUntil = _sentinel,
    DateTime? updatedAt,
    bool? deleted,
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
      snoozedUntil: snoozedUntil == _sentinel
          ? this.snoozedUntil
          : snoozedUntil as DateTime?,
      updatedAt: updatedAt ?? this.updatedAt,
      deleted: deleted ?? this.deleted,
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
        if (snoozedUntil != null) 'su': snoozedUntil!.toIso8601String(),
        'ua': updatedAt.toIso8601String(),
        if (deleted) 'del': true,
      };

  factory Alarm.fromJson(Map<String, dynamic> json) {
    final triggeredAt = DateTime.parse(json['ta'] as String);
    return Alarm(
      id: json['id'] as String,
      type: AlarmType.values[json['tp'] as int],
      level: AlarmLevel.values[json['lv'] as int],
      status: AlarmStatus.values[json['s'] as int],
      triggeredAt: triggeredAt,
      acknowledgedBy: json['ab'] as String?,
      clearedAt:
          json['ca'] != null ? DateTime.parse(json['ca'] as String) : null,
      linkedLogId: json['ll'] as String?,
      message: json['msg'] as String?,
      snoozedUntil:
          json['su'] != null ? DateTime.parse(json['su'] as String) : null,
      updatedAt: json['ua'] != null
          ? DateTime.parse(json['ua'] as String)
          : triggeredAt,
      deleted: json['del'] as bool? ?? false,
    );
  }
}

// Sentinel object used for nullable copyWith pattern
const Object _sentinel = Object();
