import 'vessel_state.dart';

enum AisTargetStatus { active, stale, lost }

enum AisSignalSource { signalk, nmea0183, lanHost }

class AisTargetState {
  final String id;
  final String mmsi;
  final String? name;
  final String? callSign;
  final int? shipType;
  final GpsPosition? position;
  final double? sog;
  final double? cog;
  final double? heading;
  final String? navStatus;
  final String? destination;
  final DateTime? eta;
  final double? closestPointNm;
  final double? tcpaMinutes;
  final double? relativeBearingDeg;
  final double? relativeDistanceNm;
  final AisSignalSource signalSource;
  final DateTime lastUpdated;
  final AisTargetStatus status;

  const AisTargetState({
    required this.id,
    required this.mmsi,
    this.name,
    this.callSign,
    this.shipType,
    this.position,
    this.sog,
    this.cog,
    this.heading,
    this.navStatus,
    this.destination,
    this.eta,
    this.closestPointNm,
    this.tcpaMinutes,
    this.relativeBearingDeg,
    this.relativeDistanceNm,
    required this.signalSource,
    required this.lastUpdated,
    required this.status,
  });

  String get displayName => name ?? mmsi;

  int get ageSec => DateTime.now().difference(lastUpdated).inSeconds;

  AisTargetState copyWith({
    String? id,
    String? mmsi,
    Object? name = _sentinel,
    Object? callSign = _sentinel,
    Object? shipType = _sentinel,
    Object? position = _sentinel,
    Object? sog = _sentinel,
    Object? cog = _sentinel,
    Object? heading = _sentinel,
    Object? navStatus = _sentinel,
    Object? destination = _sentinel,
    Object? eta = _sentinel,
    Object? closestPointNm = _sentinel,
    Object? tcpaMinutes = _sentinel,
    Object? relativeBearingDeg = _sentinel,
    Object? relativeDistanceNm = _sentinel,
    AisSignalSource? signalSource,
    DateTime? lastUpdated,
    AisTargetStatus? status,
  }) {
    return AisTargetState(
      id: id ?? this.id,
      mmsi: mmsi ?? this.mmsi,
      name: name == _sentinel ? this.name : name as String?,
      callSign: callSign == _sentinel ? this.callSign : callSign as String?,
      shipType: shipType == _sentinel ? this.shipType : shipType as int?,
      position:
          position == _sentinel ? this.position : position as GpsPosition?,
      sog: sog == _sentinel ? this.sog : sog as double?,
      cog: cog == _sentinel ? this.cog : cog as double?,
      heading: heading == _sentinel ? this.heading : heading as double?,
      navStatus:
          navStatus == _sentinel ? this.navStatus : navStatus as String?,
      destination:
          destination == _sentinel ? this.destination : destination as String?,
      eta: eta == _sentinel ? this.eta : eta as DateTime?,
      closestPointNm: closestPointNm == _sentinel
          ? this.closestPointNm
          : closestPointNm as double?,
      tcpaMinutes:
          tcpaMinutes == _sentinel ? this.tcpaMinutes : tcpaMinutes as double?,
      relativeBearingDeg: relativeBearingDeg == _sentinel
          ? this.relativeBearingDeg
          : relativeBearingDeg as double?,
      relativeDistanceNm: relativeDistanceNm == _sentinel
          ? this.relativeDistanceNm
          : relativeDistanceNm as double?,
      signalSource: signalSource ?? this.signalSource,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'mmsi': mmsi,
        if (name != null) 'nm': name,
        if (callSign != null) 'cs': callSign,
        if (shipType != null) 'st': shipType,
        if (position != null) 'pos': position!.toJson(),
        if (sog != null) 'sog': sog,
        if (cog != null) 'cog': cog,
        if (heading != null) 'hdg': heading,
        if (navStatus != null) 'ns': navStatus,
        if (destination != null) 'dst': destination,
        if (eta != null) 'eta': eta!.toIso8601String(),
        if (closestPointNm != null) 'cpa': closestPointNm,
        if (tcpaMinutes != null) 'tcpa': tcpaMinutes,
        if (relativeBearingDeg != null) 'rb': relativeBearingDeg,
        if (relativeDistanceNm != null) 'rd': relativeDistanceNm,
        'src': signalSource.index,
        'lu': lastUpdated.toIso8601String(),
        's': status.index,
      };

  factory AisTargetState.fromJson(Map<String, dynamic> json) {
    return AisTargetState(
      id: json['id'] as String,
      mmsi: json['mmsi'] as String,
      name: json['nm'] as String?,
      callSign: json['cs'] as String?,
      shipType: json['st'] as int?,
      position: json['pos'] != null
          ? GpsPosition.fromJson(json['pos'] as Map<String, dynamic>)
          : null,
      sog: json['sog'] != null ? (json['sog'] as num).toDouble() : null,
      cog: json['cog'] != null ? (json['cog'] as num).toDouble() : null,
      heading: json['hdg'] != null ? (json['hdg'] as num).toDouble() : null,
      navStatus: json['ns'] as String?,
      destination: json['dst'] as String?,
      eta: json['eta'] != null ? DateTime.parse(json['eta'] as String) : null,
      closestPointNm:
          json['cpa'] != null ? (json['cpa'] as num).toDouble() : null,
      tcpaMinutes:
          json['tcpa'] != null ? (json['tcpa'] as num).toDouble() : null,
      relativeBearingDeg:
          json['rb'] != null ? (json['rb'] as num).toDouble() : null,
      relativeDistanceNm:
          json['rd'] != null ? (json['rd'] as num).toDouble() : null,
      signalSource: AisSignalSource.values[json['src'] as int],
      lastUpdated: DateTime.parse(json['lu'] as String),
      status: AisTargetStatus.values[json['s'] as int],
    );
  }
}

// Sentinel object used for nullable copyWith pattern
const Object _sentinel = Object();

class AisOwnShipState {
  final String? mmsi;
  final String? name;
  final String? callSign;
  final int? shipType;
  final GpsPosition? position;
  final double? sog;
  final double? cog;
  final double? heading;
  final String? navStatus;
  final DateTime? lastUpdated;

  const AisOwnShipState({
    this.mmsi,
    this.name,
    this.callSign,
    this.shipType,
    this.position,
    this.sog,
    this.cog,
    this.heading,
    this.navStatus,
    this.lastUpdated,
  });

  AisOwnShipState copyWith({
    Object? mmsi = _sentinel,
    Object? name = _sentinel,
    Object? callSign = _sentinel,
    Object? shipType = _sentinel,
    Object? position = _sentinel,
    Object? sog = _sentinel,
    Object? cog = _sentinel,
    Object? heading = _sentinel,
    Object? navStatus = _sentinel,
    Object? lastUpdated = _sentinel,
  }) {
    return AisOwnShipState(
      mmsi: mmsi == _sentinel ? this.mmsi : mmsi as String?,
      name: name == _sentinel ? this.name : name as String?,
      callSign: callSign == _sentinel ? this.callSign : callSign as String?,
      shipType: shipType == _sentinel ? this.shipType : shipType as int?,
      position:
          position == _sentinel ? this.position : position as GpsPosition?,
      sog: sog == _sentinel ? this.sog : sog as double?,
      cog: cog == _sentinel ? this.cog : cog as double?,
      heading: heading == _sentinel ? this.heading : heading as double?,
      navStatus:
          navStatus == _sentinel ? this.navStatus : navStatus as String?,
      lastUpdated: lastUpdated == _sentinel
          ? this.lastUpdated
          : lastUpdated as DateTime?,
    );
  }

  Map<String, dynamic> toJson() => {
        if (mmsi != null) 'mmsi': mmsi,
        if (name != null) 'nm': name,
        if (callSign != null) 'cs': callSign,
        if (shipType != null) 'st': shipType,
        if (position != null) 'pos': position!.toJson(),
        if (sog != null) 'sog': sog,
        if (cog != null) 'cog': cog,
        if (heading != null) 'hdg': heading,
        if (navStatus != null) 'ns': navStatus,
        if (lastUpdated != null) 'lu': lastUpdated!.toIso8601String(),
      };

  factory AisOwnShipState.fromJson(Map<String, dynamic> json) {
    return AisOwnShipState(
      mmsi: json['mmsi'] as String?,
      name: json['nm'] as String?,
      callSign: json['cs'] as String?,
      shipType: json['st'] as int?,
      position: json['pos'] != null
          ? GpsPosition.fromJson(json['pos'] as Map<String, dynamic>)
          : null,
      sog: json['sog'] != null ? (json['sog'] as num).toDouble() : null,
      cog: json['cog'] != null ? (json['cog'] as num).toDouble() : null,
      heading: json['hdg'] != null ? (json['hdg'] as num).toDouble() : null,
      navStatus: json['ns'] as String?,
      lastUpdated:
          json['lu'] != null ? DateTime.parse(json['lu'] as String) : null,
    );
  }
}
