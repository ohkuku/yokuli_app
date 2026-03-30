import 'vessel_state.dart';

enum VoyageStatus { active, ended }

enum VoyageSource { auto, manual }

class VoyageSession {
  final String id;
  final DateTime startTime;
  final DateTime? endTime;
  final GpsPosition? startPosition;
  final GpsPosition? endPosition;
  final VoyageStatus status;
  final VoyageSource source;
  final String? name;   // custom alias/title set by user
  final String? notes;  // free-text voyage notes

  const VoyageSession({
    required this.id,
    required this.startTime,
    this.endTime,
    this.startPosition,
    this.endPosition,
    required this.status,
    required this.source,
    this.name,
    this.notes,
  });

  bool get isActive => status == VoyageStatus.active;

  /// Display title: custom name if set, otherwise formatted start time.
  String get displayTitle => name != null && name!.isNotEmpty
      ? name!
      : '航行 ${startTime.toLocal().toString().substring(0, 16)}';

  Duration get duration =>
      endTime?.difference(startTime) ?? DateTime.now().difference(startTime);

  VoyageSession copyWith({
    String? id,
    DateTime? startTime,
    Object? endTime = _sentinel,
    Object? startPosition = _sentinel,
    Object? endPosition = _sentinel,
    VoyageStatus? status,
    VoyageSource? source,
    Object? name = _sentinel,
    Object? notes = _sentinel,
  }) {
    return VoyageSession(
      id: id ?? this.id,
      startTime: startTime ?? this.startTime,
      endTime: endTime == _sentinel ? this.endTime : endTime as DateTime?,
      startPosition: startPosition == _sentinel
          ? this.startPosition
          : startPosition as GpsPosition?,
      endPosition: endPosition == _sentinel
          ? this.endPosition
          : endPosition as GpsPosition?,
      status: status ?? this.status,
      source: source ?? this.source,
      name: name == _sentinel ? this.name : name as String?,
      notes: notes == _sentinel ? this.notes : notes as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'st': startTime.toIso8601String(),
        if (endTime != null) 'et': endTime!.toIso8601String(),
        if (startPosition != null) 'sp': startPosition!.toJson(),
        if (endPosition != null) 'ep': endPosition!.toJson(),
        'vs': status.index,
        'src': source.index,
        if (name != null) 'nm': name,
        if (notes != null) 'nts': notes,
      };

  factory VoyageSession.fromJson(Map<String, dynamic> json) {
    return VoyageSession(
      id: json['id'] as String,
      startTime: DateTime.parse(json['st'] as String),
      endTime: json['et'] != null ? DateTime.parse(json['et'] as String) : null,
      startPosition: json['sp'] != null
          ? GpsPosition.fromJson(json['sp'] as Map<String, dynamic>)
          : null,
      endPosition: json['ep'] != null
          ? GpsPosition.fromJson(json['ep'] as Map<String, dynamic>)
          : null,
      status: VoyageStatus.values[json['vs'] as int],
      source: VoyageSource.values[json['src'] as int],
      name: json['nm'] as String?,
      notes: json['nts'] as String?,
    );
  }
}

// Sentinel object used for nullable copyWith pattern
const Object _sentinel = Object();
