class NotificationReceipt {
  /// Composite ID: "receipt_${notificationId}_${deviceId}".
  final String id;

  final String notificationId;
  final String deviceId;
  final DateTime dismissedAt;

  // Sync envelope
  final DateTime updatedAt;
  final bool deleted;

  /// Device-scoped: "device:${deviceId}".
  final String scope;
  final String sourceDeviceId;

  /// Always 1.
  final int schemaVersion;

  const NotificationReceipt({
    required this.id,
    required this.notificationId,
    required this.deviceId,
    required this.dismissedAt,
    required this.updatedAt,
    this.deleted = false,
    required this.scope,
    required this.sourceDeviceId,
    this.schemaVersion = 1,
  });

  /// Convenience factory that automatically builds the composite [id] and
  /// device-scoped [scope] from [notifId] and [deviceId].
  factory NotificationReceipt.create({
    required String notifId,
    required String deviceId,
  }) {
    final now = DateTime.now();
    return NotificationReceipt(
      id: 'receipt_${notifId}_$deviceId',
      notificationId: notifId,
      deviceId: deviceId,
      dismissedAt: now,
      updatedAt: now,
      deleted: false,
      scope: 'device:$deviceId',
      sourceDeviceId: deviceId,
      schemaVersion: 1,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'nid': notificationId,
        'devId': deviceId,
        'da': dismissedAt.toIso8601String(),
        'ua': updatedAt.toIso8601String(),
        if (deleted) 'del': true,
        'scope': scope,
        'src': sourceDeviceId,
        'sv': schemaVersion,
      };

  factory NotificationReceipt.fromJson(Map<String, dynamic> json) {
    final dismissedAt = DateTime.parse(json['da'] as String);
    final deviceId = json['devId'] as String? ?? '';
    return NotificationReceipt(
      id: json['id'] as String,
      notificationId: json['nid'] as String,
      deviceId: deviceId,
      dismissedAt: dismissedAt,
      updatedAt: json['ua'] != null
          ? DateTime.parse(json['ua'] as String)
          : dismissedAt,
      deleted: json['del'] as bool? ?? false,
      scope: json['scope'] as String? ?? 'device:$deviceId',
      sourceDeviceId: json['src'] as String? ?? '',
      schemaVersion: json['sv'] as int? ?? 1,
    );
  }
}
