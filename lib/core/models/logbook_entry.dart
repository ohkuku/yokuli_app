import 'vessel_state.dart';
import '../utils/id_gen.dart';

/// Type of logbook entry
enum LogbookEntryType {
  departure,
  arrival,
  waypoint,
  mob,
  weather,
  manual,
  auto,
}

/// A single logbook entry stored in Hive as Map
class LogbookEntry {
  final String id;
  final DateTime timestamp;
  final LogbookEntryType type;
  final GpsPosition? position;
  final String notes;
  final double? speedOverGround;
  final double? courseOverGround;
  final double? windSpeed;
  final double? windDirection;
  final double? depth;

  const LogbookEntry({
    required this.id,
    required this.timestamp,
    required this.type,
    this.position,
    this.notes = '',
    this.speedOverGround,
    this.courseOverGround,
    this.windSpeed,
    this.windDirection,
    this.depth,
  });

  /// Create from current vessel state
  factory LogbookEntry.fromVesselState(
    VesselState state, {
    required LogbookEntryType type,
    String notes = '',
  }) =>
      LogbookEntry(
        id: generateId(),
        timestamp: DateTime.now(),
        type: type,
        position: state.position,
        notes: notes,
        speedOverGround: state.speedOverGround,
        courseOverGround: state.courseOverGround,
        windSpeed: state.trueWindSpeed,
        windDirection: state.trueWindDirection,
        depth: state.depthBelowKeel,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'ts': timestamp.toIso8601String(),
        'type': type.name,
        if (position != null) 'pos': position!.toJson(),
        'notes': notes,
        if (speedOverGround != null) 'sog': speedOverGround,
        if (courseOverGround != null) 'cog': courseOverGround,
        if (windSpeed != null) 'ws': windSpeed,
        if (windDirection != null) 'wd': windDirection,
        if (depth != null) 'dpt': depth,
      };

  factory LogbookEntry.fromMap(Map<dynamic, dynamic> map) => LogbookEntry(
        id: map['id'] as String,
        timestamp: DateTime.parse(map['ts'] as String),
        type: LogbookEntryType.values.firstWhere(
          (e) => e.name == map['type'],
          orElse: () => LogbookEntryType.manual,
        ),
        position: map['pos'] != null
            ? GpsPosition.fromJson(Map<String, dynamic>.from(map['pos'] as Map))
            : null,
        notes: (map['notes'] as String?) ?? '',
        speedOverGround: map['sog'] != null ? (map['sog'] as num).toDouble() : null,
        courseOverGround: map['cog'] != null ? (map['cog'] as num).toDouble() : null,
        windSpeed: map['ws'] != null ? (map['ws'] as num).toDouble() : null,
        windDirection: map['wd'] != null ? (map['wd'] as num).toDouble() : null,
        depth: map['dpt'] != null ? (map['dpt'] as num).toDouble() : null,
      );
}
