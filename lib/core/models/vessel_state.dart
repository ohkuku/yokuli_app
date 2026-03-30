import 'dart:math' as math;

/// GPS position fix
class GpsPosition {
  final double latitude;
  final double longitude;
  final double? altitude;
  final DateTime timestamp;

  const GpsPosition({
    required this.latitude,
    required this.longitude,
    this.altitude,
    required this.timestamp,
  });

  GpsPosition copyWith({
    double? latitude,
    double? longitude,
    double? altitude,
    DateTime? timestamp,
  }) =>
      GpsPosition(
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        altitude: altitude ?? this.altitude,
        timestamp: timestamp ?? this.timestamp,
      );

  Map<String, dynamic> toJson() => {
        'lat': latitude,
        'lon': longitude,
        if (altitude != null) 'alt': altitude,
        'ts': timestamp.toIso8601String(),
      };

  factory GpsPosition.fromJson(Map<String, dynamic> json) => GpsPosition(
        latitude: (json['lat'] as num).toDouble(),
        longitude: (json['lon'] as num).toDouble(),
        altitude: json['alt'] != null ? (json['alt'] as num).toDouble() : null,
        timestamp: DateTime.parse(json['ts'] as String),
      );

  /// Distance to another position in nautical miles
  double distanceTo(GpsPosition other) {
    const r = 3440.065; // Earth radius in nautical miles
    final lat1 = latitude * math.pi / 180;
    final lat2 = other.latitude * math.pi / 180;
    final dLat = (other.latitude - latitude) * math.pi / 180;
    final dLon = (other.longitude - longitude) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) * math.cos(lat2) * math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  /// Bearing to another position in degrees true
  double bearingTo(GpsPosition other) {
    final lat1 = latitude * math.pi / 180;
    final lat2 = other.latitude * math.pi / 180;
    final dLon = (other.longitude - longitude) * math.pi / 180;
    final y = math.sin(dLon) * math.cos(lat2);
    final x =
        math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  @override
  String toString() =>
      '${latitude.toStringAsFixed(5)}°, ${longitude.toStringAsFixed(5)}°';
}

/// Battery/bank state
class BatteryState {
  final String id;
  final String name;
  final double? voltage;
  final double? current;
  final double? stateOfCharge; // 0.0 to 1.0
  final double? temperature;

  const BatteryState({
    required this.id,
    required this.name,
    this.voltage,
    this.current,
    this.stateOfCharge,
    this.temperature,
  });

  BatteryState copyWith({
    String? id,
    String? name,
    double? voltage,
    double? current,
    double? stateOfCharge,
    double? temperature,
  }) =>
      BatteryState(
        id: id ?? this.id,
        name: name ?? this.name,
        voltage: voltage ?? this.voltage,
        current: current ?? this.current,
        stateOfCharge: stateOfCharge ?? this.stateOfCharge,
        temperature: temperature ?? this.temperature,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (voltage != null) 'v': voltage,
        if (current != null) 'a': current,
        if (stateOfCharge != null) 'soc': stateOfCharge,
        if (temperature != null) 'temp': temperature,
      };

  factory BatteryState.fromJson(Map<String, dynamic> json) => BatteryState(
        id: json['id'] as String,
        name: json['name'] as String,
        voltage: json['v'] != null ? (json['v'] as num).toDouble() : null,
        current: json['a'] != null ? (json['a'] as num).toDouble() : null,
        stateOfCharge: json['soc'] != null ? (json['soc'] as num).toDouble() : null,
        temperature: json['temp'] != null ? (json['temp'] as num).toDouble() : null,
      );
}

/// Central vessel data model — all live values from Signal K / sensors
class VesselState {
  // --- Navigation ---
  final double? speedOverGround; // knots
  final double? courseOverGround; // degrees true
  final double? heading; // degrees true
  final GpsPosition? position;

  // --- Wind ---
  final double? trueWindSpeed; // knots
  final double? trueWindDirection; // degrees true
  final double? apparentWindSpeed; // knots
  final double? apparentWindAngle; // degrees, -180..+180 (neg = port)

  // --- Depth ---
  final double? depthBelowKeel; // meters
  final double? depthBelowSurface; // meters

  // --- Power ---
  final Map<String, BatteryState> batteries;

  // --- Metadata ---
  final DateTime lastUpdated;
  final String? sourceDeviceId;

  const VesselState({
    this.speedOverGround,
    this.courseOverGround,
    this.heading,
    this.position,
    this.trueWindSpeed,
    this.trueWindDirection,
    this.apparentWindSpeed,
    this.apparentWindAngle,
    this.depthBelowKeel,
    this.depthBelowSurface,
    required this.batteries,
    required this.lastUpdated,
    this.sourceDeviceId,
  });

  factory VesselState.empty() => VesselState(
        batteries: const {},
        lastUpdated: DateTime.fromMillisecondsSinceEpoch(0),
      );

  VesselState copyWith({
    double? speedOverGround,
    double? courseOverGround,
    double? heading,
    GpsPosition? position,
    double? trueWindSpeed,
    double? trueWindDirection,
    double? apparentWindSpeed,
    double? apparentWindAngle,
    double? depthBelowKeel,
    double? depthBelowSurface,
    Map<String, BatteryState>? batteries,
    DateTime? lastUpdated,
    String? sourceDeviceId,
  }) =>
      VesselState(
        speedOverGround: speedOverGround ?? this.speedOverGround,
        courseOverGround: courseOverGround ?? this.courseOverGround,
        heading: heading ?? this.heading,
        position: position ?? this.position,
        trueWindSpeed: trueWindSpeed ?? this.trueWindSpeed,
        trueWindDirection: trueWindDirection ?? this.trueWindDirection,
        apparentWindSpeed: apparentWindSpeed ?? this.apparentWindSpeed,
        apparentWindAngle: apparentWindAngle ?? this.apparentWindAngle,
        depthBelowKeel: depthBelowKeel ?? this.depthBelowKeel,
        depthBelowSurface: depthBelowSurface ?? this.depthBelowSurface,
        batteries: batteries ?? this.batteries,
        lastUpdated: lastUpdated ?? this.lastUpdated,
        sourceDeviceId: sourceDeviceId ?? this.sourceDeviceId,
      );

  Map<String, dynamic> toJson() => {
        if (speedOverGround != null) 'sog': speedOverGround,
        if (courseOverGround != null) 'cog': courseOverGround,
        if (heading != null) 'hdg': heading,
        if (position != null) 'pos': position!.toJson(),
        if (trueWindSpeed != null) 'tws': trueWindSpeed,
        if (trueWindDirection != null) 'twd': trueWindDirection,
        if (apparentWindSpeed != null) 'aws': apparentWindSpeed,
        if (apparentWindAngle != null) 'awa': apparentWindAngle,
        if (depthBelowKeel != null) 'dbt': depthBelowKeel,
        if (depthBelowSurface != null) 'dbs': depthBelowSurface,
        'batteries': batteries.map((k, v) => MapEntry(k, v.toJson())),
        'ts': lastUpdated.toIso8601String(),
        if (sourceDeviceId != null) 'src': sourceDeviceId,
      };

  factory VesselState.fromJson(Map<String, dynamic> json) => VesselState(
        speedOverGround: json['sog'] != null ? (json['sog'] as num).toDouble() : null,
        courseOverGround: json['cog'] != null ? (json['cog'] as num).toDouble() : null,
        heading: json['hdg'] != null ? (json['hdg'] as num).toDouble() : null,
        position:
            json['pos'] != null ? GpsPosition.fromJson(json['pos'] as Map<String, dynamic>) : null,
        trueWindSpeed: json['tws'] != null ? (json['tws'] as num).toDouble() : null,
        trueWindDirection: json['twd'] != null ? (json['twd'] as num).toDouble() : null,
        apparentWindSpeed: json['aws'] != null ? (json['aws'] as num).toDouble() : null,
        apparentWindAngle: json['awa'] != null ? (json['awa'] as num).toDouble() : null,
        depthBelowKeel: json['dbt'] != null ? (json['dbt'] as num).toDouble() : null,
        depthBelowSurface: json['dbs'] != null ? (json['dbs'] as num).toDouble() : null,
        batteries: json['batteries'] != null
            ? (json['batteries'] as Map<String, dynamic>).map(
                (k, v) => MapEntry(k, BatteryState.fromJson(v as Map<String, dynamic>)),
              )
            : const {},
        lastUpdated: DateTime.parse(json['ts'] as String),
        sourceDeviceId: json['src'] as String?,
      );
}
