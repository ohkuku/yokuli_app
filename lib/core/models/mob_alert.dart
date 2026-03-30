import 'vessel_state.dart';

/// Man Overboard alert
class MobAlert {
  final String id;
  final DateTime triggeredAt;
  final GpsPosition? position;
  final String triggeredByDevice;
  bool isActive;

  MobAlert({
    required this.id,
    required this.triggeredAt,
    this.position,
    required this.triggeredByDevice,
    this.isActive = true,
  });

  /// Duration since MOB triggered
  Duration get elapsed => DateTime.now().difference(triggeredAt);

  Map<String, dynamic> toJson() => {
        'id': id,
        'ts': triggeredAt.toIso8601String(),
        if (position != null) 'pos': position!.toJson(),
        'by': triggeredByDevice,
        'active': isActive,
      };

  factory MobAlert.fromJson(Map<String, dynamic> json) => MobAlert(
        id: json['id'] as String,
        triggeredAt: DateTime.parse(json['ts'] as String),
        position: json['pos'] != null
            ? GpsPosition.fromJson(json['pos'] as Map<String, dynamic>)
            : null,
        triggeredByDevice: json['by'] as String,
        isActive: json['active'] as bool? ?? true,
      );
}
