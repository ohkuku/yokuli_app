// ignore_for_file: constant_identifier_names

// ---------------------------------------------------------------------------
// Alarm condition source
// ---------------------------------------------------------------------------

enum AlarmConditionSource { vesselMetric, signalK }

// ---------------------------------------------------------------------------
// Known vessel metrics
// ---------------------------------------------------------------------------

/// Maps string metric keys to (display name, unit) tuples.
/// The evaluator layer maps these keys to VesselState fields.
const vesselMetrics = {
  'sog': ('Speed Over Ground', 'kn'),
  'depth_keel': ('Depth Below Keel', 'm'),
  'depth_surface': ('Depth Below Surface', 'm'),
  'battery_voltage_main': ('Main Battery Voltage', 'V'),
  'wind_true_speed': ('True Wind Speed', 'kn'),
  'wind_apparent_speed': ('Apparent Wind Speed', 'kn'),
  'solar_power_total': ('Solar Power Total', 'W'),
};

// ---------------------------------------------------------------------------
// AlarmOperator
// ---------------------------------------------------------------------------

enum AlarmOperator { greaterEqual, lessEqual, greaterThan, lessThan }

extension AlarmOperatorExt on AlarmOperator {
  String get symbol {
    switch (this) {
      case AlarmOperator.greaterEqual:
        return '>=';
      case AlarmOperator.lessEqual:
        return '<=';
      case AlarmOperator.greaterThan:
        return '>';
      case AlarmOperator.lessThan:
        return '<';
    }
  }

  bool evaluate(double value, double threshold) {
    switch (this) {
      case AlarmOperator.greaterEqual:
        return value >= threshold;
      case AlarmOperator.lessEqual:
        return value <= threshold;
      case AlarmOperator.greaterThan:
        return value > threshold;
      case AlarmOperator.lessThan:
        return value < threshold;
    }
  }
}

// ---------------------------------------------------------------------------
// AlarmCondition
// ---------------------------------------------------------------------------

class AlarmCondition {
  final AlarmConditionSource source;

  /// Key from [vesselMetrics] (for vesselMetric source) or SignalK path.
  final String metric;

  final AlarmOperator operator;
  final double threshold;

  /// How long (in milliseconds) the condition must persist before triggering.
  /// Null means trigger immediately.
  final int? sustainMs;

  /// Hysteresis band: condition must recover by this amount before it can
  /// re-trigger. Null means no hysteresis.
  final double? hysteresis;

  /// Minimum milliseconds between new instances of this rule (default 300000 = 5 min).
  final int cooldownMs;

  const AlarmCondition({
    required this.source,
    required this.metric,
    required this.operator,
    required this.threshold,
    this.sustainMs,
    this.hysteresis,
    this.cooldownMs = 300000,
  });

  Map<String, dynamic> toJson() => {
        'src': source.index,
        'metric': metric,
        'op': operator.index,
        'thr': threshold,
        if (sustainMs != null) 'sustain': sustainMs,
        if (hysteresis != null) 'hyst': hysteresis,
        'cooldown': cooldownMs,
      };

  factory AlarmCondition.fromJson(Map<String, dynamic> json) {
    return AlarmCondition(
      source: AlarmConditionSource.values[json['src'] as int? ?? 0],
      metric: json['metric'] as String,
      operator: AlarmOperator.values[json['op'] as int],
      threshold: (json['thr'] as num).toDouble(),
      sustainMs: json['sustain'] as int?,
      hysteresis: json['hyst'] != null ? (json['hyst'] as num).toDouble() : null,
      cooldownMs: json['cooldown'] as int? ?? 300000,
    );
  }
}

// ---------------------------------------------------------------------------
// AlarmResponsePlan
// ---------------------------------------------------------------------------

class AlarmResponsePlan {
  final bool inApp;
  final bool sound;
  final bool discord;

  /// If set, repeat the notification every this many milliseconds while active.
  final int? repeatEveryMs;

  const AlarmResponsePlan({
    this.inApp = true,
    this.sound = true,
    this.discord = false,
    this.repeatEveryMs,
  });

  AlarmResponsePlan copyWith({
    bool? inApp,
    bool? sound,
    bool? discord,
    Object? repeatEveryMs = _sentinel,
  }) {
    return AlarmResponsePlan(
      inApp: inApp ?? this.inApp,
      sound: sound ?? this.sound,
      discord: discord ?? this.discord,
      repeatEveryMs: repeatEveryMs == _sentinel
          ? this.repeatEveryMs
          : repeatEveryMs as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'inApp': inApp,
        'sound': sound,
        'discord': discord,
        if (repeatEveryMs != null) 'repeatMs': repeatEveryMs,
      };

  factory AlarmResponsePlan.fromJson(Map<String, dynamic> json) {
    return AlarmResponsePlan(
      inApp: json['inApp'] as bool? ?? true,
      sound: json['sound'] as bool? ?? true,
      discord: json['discord'] as bool? ?? false,
      repeatEveryMs: json['repeatMs'] as int?,
    );
  }
}

// ---------------------------------------------------------------------------
// AlarmLevel
// ---------------------------------------------------------------------------

enum AlarmLevel { critical, warning, info }

extension AlarmLevelExt on AlarmLevel {
  String get displayName {
    switch (this) {
      case AlarmLevel.critical:
        return '严重';
      case AlarmLevel.warning:
        return '警告';
      case AlarmLevel.info:
        return '提示';
    }
  }

  /// Hex color string (no Flutter dependency).
  String get colorHex {
    switch (this) {
      case AlarmLevel.critical:
        return '#F44336';
      case AlarmLevel.warning:
        return '#FF9800';
      case AlarmLevel.info:
        return '#2196F3';
    }
  }
}

// ---------------------------------------------------------------------------
// AlarmRule
// ---------------------------------------------------------------------------

// Sentinel for nullable copyWith
const Object _sentinel = Object();

class AlarmRule {
  final String id;
  final String name;
  final bool enabled;
  final AlarmLevel level;
  final AlarmCondition condition;
  final AlarmResponsePlan responsePlan;

  /// 0 = cannot snooze.
  final int snoozeMins;

  /// Built-in rules cannot be deleted, though thresholds may be editable.
  final bool isBuiltIn;

  // Sync envelope — JSON keys use abbreviated forms for wire compatibility.
  final DateTime updatedAt;
  final bool deleted;

  /// Always 'global'.
  final String scope;
  final String sourceDeviceId;

  /// Always 1.
  final int schemaVersion;

  const AlarmRule({
    required this.id,
    required this.name,
    required this.enabled,
    required this.level,
    required this.condition,
    required this.responsePlan,
    required this.snoozeMins,
    required this.isBuiltIn,
    required this.updatedAt,
    this.deleted = false,
    this.scope = 'global',
    required this.sourceDeviceId,
    this.schemaVersion = 1,
  });

  AlarmRule copyWith({
    String? id,
    String? name,
    bool? enabled,
    AlarmLevel? level,
    AlarmCondition? condition,
    AlarmResponsePlan? responsePlan,
    int? snoozeMins,
    bool? isBuiltIn,
    DateTime? updatedAt,
    bool? deleted,
    String? scope,
    String? sourceDeviceId,
    int? schemaVersion,
  }) {
    return AlarmRule(
      id: id ?? this.id,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      level: level ?? this.level,
      condition: condition ?? this.condition,
      responsePlan: responsePlan ?? this.responsePlan,
      snoozeMins: snoozeMins ?? this.snoozeMins,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
      updatedAt: updatedAt ?? this.updatedAt,
      deleted: deleted ?? this.deleted,
      scope: scope ?? this.scope,
      sourceDeviceId: sourceDeviceId ?? this.sourceDeviceId,
      schemaVersion: schemaVersion ?? this.schemaVersion,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'enabled': enabled,
        'lv': level.index,
        'cond': condition.toJson(),
        'resp': responsePlan.toJson(),
        'snoozeMins': snoozeMins,
        'builtIn': isBuiltIn,
        'ua': updatedAt.toIso8601String(),
        if (deleted) 'del': true,
        'scope': scope,
        'src': sourceDeviceId,
        'sv': schemaVersion,
      };

  factory AlarmRule.fromJson(Map<String, dynamic> json) {
    return AlarmRule(
      id: json['id'] as String,
      name: json['name'] as String,
      enabled: json['enabled'] as bool? ?? true,
      level: AlarmLevel.values[json['lv'] as int? ?? AlarmLevel.warning.index],
      condition: AlarmCondition.fromJson(json['cond'] as Map<String, dynamic>),
      responsePlan: AlarmResponsePlan.fromJson(
          json['resp'] as Map<String, dynamic>? ?? {}),
      snoozeMins: json['snoozeMins'] as int? ?? 15,
      isBuiltIn: json['builtIn'] as bool? ?? false,
      updatedAt: json['ua'] != null
          ? DateTime.parse(json['ua'] as String)
          : DateTime.fromMillisecondsSinceEpoch(0),
      deleted: json['del'] as bool? ?? false,
      scope: json['scope'] as String? ?? 'global',
      sourceDeviceId: json['src'] as String? ?? '',
      schemaVersion: json['sv'] as int? ?? 1,
    );
  }
}

// ---------------------------------------------------------------------------
// NotifyChannelConfig
// ---------------------------------------------------------------------------

class NotifyChannelConfig {
  final bool discordEnabled;
  final String discordWebhookUrl;
  final AlarmLevel discordMinLevel;

  const NotifyChannelConfig({
    this.discordEnabled = false,
    this.discordWebhookUrl = '',
    this.discordMinLevel = AlarmLevel.critical,
  });

  NotifyChannelConfig copyWith({
    bool? discordEnabled,
    String? discordWebhookUrl,
    AlarmLevel? discordMinLevel,
  }) {
    return NotifyChannelConfig(
      discordEnabled: discordEnabled ?? this.discordEnabled,
      discordWebhookUrl: discordWebhookUrl ?? this.discordWebhookUrl,
      discordMinLevel: discordMinLevel ?? this.discordMinLevel,
    );
  }

  Map<String, dynamic> toJson() => {
        'discordEnabled': discordEnabled,
        'discordWebhookUrl': discordWebhookUrl,
        'discordMinLevel': discordMinLevel.index,
      };

  factory NotifyChannelConfig.fromJson(Map<String, dynamic> json) {
    return NotifyChannelConfig(
      discordEnabled: json['discordEnabled'] as bool? ?? false,
      discordWebhookUrl: json['discordWebhookUrl'] as String? ?? '',
      discordMinLevel: AlarmLevel.values[
          json['discordMinLevel'] as int? ?? AlarmLevel.critical.index],
    );
  }
}
