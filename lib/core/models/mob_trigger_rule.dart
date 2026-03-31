/// Auto-trigger rule for MOB (Man Overboard) detection.
///
/// Supported trigger types:
///   - [MobTriggerType.signalkPath]         — fires when any value appears on a
///     specific SignalK path.
///   - [MobTriggerType.signalkNotification] — fires when a `notifications.*`
///     path carries a matching state (emergency / alarm / …).
///   - [MobTriggerType.nmeaSentence]        — fires when a raw NMEA 0183
///     sentence (forwarded by the SK server via the `sentences` path) matches
///     by talker ID + sentence type, with an optional keyword check.
enum MobTriggerType {
  signalkPath,
  signalkNotification,
  nmeaSentence,
}

/// Human-readable labels for each [MobTriggerType].
extension MobTriggerTypeLabel on MobTriggerType {
  String get label {
    switch (this) {
      case MobTriggerType.signalkPath:
        return 'SignalK 路径';
      case MobTriggerType.signalkNotification:
        return 'SignalK 通知';
      case MobTriggerType.nmeaSentence:
        return 'NMEA 0183 指令';
    }
  }

  String get description {
    switch (this) {
      case MobTriggerType.signalkPath:
        return '当指定 SK 路径出现任意值时触发';
      case MobTriggerType.signalkNotification:
        return '当 notifications.* 命名空间出现特定状态时触发';
      case MobTriggerType.nmeaSentence:
        return '当 SK 服务器转发指定 NMEA 句子类型时触发';
    }
  }
}

/// A user-defined rule that can auto-trigger a MOB alert.
class MobTriggerRule {
  final String id;
  final String name;
  final bool enabled;
  final MobTriggerType type;

  /// Type-specific configuration.
  ///
  /// **signalkPath** keys:
  ///   `path` (String) — SK path to watch.
  ///   `matchStateEquals` (String, optional) — only trigger if the value map
  ///   contains a `state` key equal to this string.
  ///
  /// **signalkNotification** keys:
  ///   `pathPattern` (String) — substring that the path after `notifications.`
  ///   must contain (e.g. `'mob'` matches `notifications.mob` and
  ///   `notifications.mob.position`).
  ///   `states` (List<String>) — trigger when the notification's `state` field
  ///   is in this list (e.g. `['emergency', 'alarm']`).
  ///
  /// **nmeaSentence** keys:
  ///   `talkerId` (String) — 2-char talker ID (empty = any, e.g. `'AI'`).
  ///   `sentenceType` (String) — 3-char sentence type (e.g. `'MOB'`, `'VSD'`).
  ///   `keyword` (String, optional) — case-insensitive keyword that must appear
  ///   anywhere in the raw sentence string.
  final Map<String, dynamic> config;

  final DateTime createdAt;
  final DateTime updatedAt;

  const MobTriggerRule({
    required this.id,
    required this.name,
    required this.enabled,
    required this.type,
    required this.config,
    required this.createdAt,
    required this.updatedAt,
  });

  MobTriggerRule copyWith({
    String? name,
    bool? enabled,
    MobTriggerType? type,
    Map<String, dynamic>? config,
    DateTime? updatedAt,
  }) =>
      MobTriggerRule(
        id: id,
        name: name ?? this.name,
        enabled: enabled ?? this.enabled,
        type: type ?? this.type,
        config: config ?? this.config,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'enabled': enabled,
        'type': type.name,
        'config': config,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory MobTriggerRule.fromJson(Map<String, dynamic> json) => MobTriggerRule(
        id: json['id'] as String,
        name: json['name'] as String,
        enabled: json['enabled'] as bool? ?? true,
        type: MobTriggerType.values.byName(json['type'] as String),
        config: Map<String, dynamic>.from(json['config'] as Map),
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );

  // ── Built-in presets ────────────────────────────────────────────────────────

  static MobTriggerRule presetSignalKNotification({
    required String id,
    required DateTime now,
  }) =>
      MobTriggerRule(
        id: id,
        name: 'SignalK MOB 通知',
        enabled: true,
        type: MobTriggerType.signalkNotification,
        config: {
          'pathPattern': 'mob',
          'states': ['emergency', 'alarm'],
        },
        createdAt: now,
        updatedAt: now,
      );

  static MobTriggerRule presetNmeaMob({
    required String id,
    required DateTime now,
  }) =>
      MobTriggerRule(
        id: id,
        name: 'NMEA 0183 MOB 指令',
        enabled: true,
        type: MobTriggerType.nmeaSentence,
        config: {
          'talkerId': '',      // any talker
          'sentenceType': 'MOB',
        },
        createdAt: now,
        updatedAt: now,
      );

  static MobTriggerRule presetNmeaAisSafety({
    required String id,
    required DateTime now,
  }) =>
      MobTriggerRule(
        id: id,
        name: 'AIS 安全广播 (MOB 关键字)',
        enabled: true,
        type: MobTriggerType.nmeaSentence,
        config: {
          'talkerId': 'AI',
          'sentenceType': 'VSD',
          'keyword': 'MOB',
        },
        createdAt: now,
        updatedAt: now,
      );

  static MobTriggerRule presetSkPathManOverboard({
    required String id,
    required DateTime now,
  }) =>
      MobTriggerRule(
        id: id,
        name: 'SignalK man-overboard 路径',
        enabled: true,
        type: MobTriggerType.signalkPath,
        config: {
          'path': 'notifications.man-overboard',
        },
        createdAt: now,
        updatedAt: now,
      );
}
