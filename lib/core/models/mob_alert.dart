import 'vessel_state.dart';

/// Man Overboard alert
class MobAlert {
  final String id;
  final DateTime triggeredAt;
  final GpsPosition? position;
  final String triggeredByDevice;
  bool isActive;

  /// How this MOB was triggered: `'manual'` or `'rule'`.
  final String triggerSource;

  /// Name of the rule that triggered this MOB, or null for manual.
  final String? triggerRuleName;

  /// When the MOB was cleared (recovered), or null if still active.
  final DateTime? clearedAt;

  MobAlert({
    required this.id,
    required this.triggeredAt,
    this.position,
    required this.triggeredByDevice,
    this.isActive = true,
    this.triggerSource = 'manual',
    this.triggerRuleName,
    this.clearedAt,
  });

  /// Duration since MOB triggered (if still active) or total duration.
  Duration get elapsed => (clearedAt ?? DateTime.now()).difference(triggeredAt);

  MobAlert copyWith({
    bool? isActive,
    DateTime? clearedAt,
  }) =>
      MobAlert(
        id: id,
        triggeredAt: triggeredAt,
        position: position,
        triggeredByDevice: triggeredByDevice,
        isActive: isActive ?? this.isActive,
        triggerSource: triggerSource,
        triggerRuleName: triggerRuleName,
        clearedAt: clearedAt ?? this.clearedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'ts': triggeredAt.toIso8601String(),
        if (position != null) 'pos': position!.toJson(),
        'by': triggeredByDevice,
        'active': isActive,
        'src': triggerSource,
        if (triggerRuleName != null) 'rn': triggerRuleName,
        if (clearedAt != null) 'clAt': clearedAt!.toIso8601String(),
      };

  factory MobAlert.fromJson(Map<String, dynamic> json) => MobAlert(
        id: json['id'] as String,
        triggeredAt: DateTime.parse(json['ts'] as String),
        position: json['pos'] != null
            ? GpsPosition.fromJson(json['pos'] as Map<String, dynamic>)
            : null,
        triggeredByDevice: json['by'] as String,
        isActive: json['active'] as bool? ?? true,
        triggerSource: json['src'] as String? ?? 'manual',
        triggerRuleName: json['rn'] as String?,
        clearedAt: json['clAt'] != null
            ? DateTime.tryParse(json['clAt'] as String)
            : null,
      );
}
