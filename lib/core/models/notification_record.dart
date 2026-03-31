enum NotificationSeverity { critical, warning, info }

enum NotificationType { alarm, mob, taskDue, system }

class NotificationRecord {
  final String id;
  final NotificationType type;
  final NotificationSeverity severity;
  final String title;
  final String body;

  /// ID of the related entity, e.g. an AlarmInstance ID.
  final String? linkedEntityId;

  final DateTime createdAt;

  // Sync envelope
  final DateTime updatedAt;
  final bool deleted;

  /// Always 'global'.
  final String scope;
  final String sourceDeviceId;

  /// Always 1.
  final int schemaVersion;

  const NotificationRecord({
    required this.id,
    required this.type,
    required this.severity,
    required this.title,
    required this.body,
    this.linkedEntityId,
    required this.createdAt,
    required this.updatedAt,
    this.deleted = false,
    this.scope = 'global',
    required this.sourceDeviceId,
    this.schemaVersion = 1,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'tp': type.index,
        'sev': severity.index,
        'title': title,
        'body': body,
        if (linkedEntityId != null) 'lei': linkedEntityId,
        'ca': createdAt.toIso8601String(),
        'ua': updatedAt.toIso8601String(),
        if (deleted) 'del': true,
        'scope': scope,
        'src': sourceDeviceId,
        'sv': schemaVersion,
      };

  factory NotificationRecord.fromJson(Map<String, dynamic> json) {
    final createdAt = DateTime.parse(json['ca'] as String);
    return NotificationRecord(
      id: json['id'] as String,
      type: NotificationType.values[json['tp'] as int? ?? 0],
      severity: NotificationSeverity.values[json['sev'] as int? ?? 1],
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      linkedEntityId: json['lei'] as String?,
      createdAt: createdAt,
      updatedAt: json['ua'] != null
          ? DateTime.parse(json['ua'] as String)
          : createdAt,
      deleted: json['del'] as bool? ?? false,
      scope: json['scope'] as String? ?? 'global',
      sourceDeviceId: json['src'] as String? ?? '',
      schemaVersion: json['sv'] as int? ?? 1,
    );
  }
}
