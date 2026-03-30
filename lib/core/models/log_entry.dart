import 'vessel_state.dart';

enum LogEntryType { system, alarm, navigation, maintenance, manual, power, ais }

class LogContext {
  final GpsPosition? position;
  final double? sog;
  final double? cog;
  final double? heading;
  final double? depth;
  final double? batteryVoltage;
  final double? solarPower;
  final List<String> activeAlarmIds;
  final String? aisTargetId;

  const LogContext({
    this.position,
    this.sog,
    this.cog,
    this.heading,
    this.depth,
    this.batteryVoltage,
    this.solarPower,
    required this.activeAlarmIds,
    this.aisTargetId,
  });

  Map<String, dynamic> toJson() => {
        if (position != null) 'pos': position!.toJson(),
        if (sog != null) 'sog': sog,
        if (cog != null) 'cog': cog,
        if (heading != null) 'hdg': heading,
        if (depth != null) 'dep': depth,
        if (batteryVoltage != null) 'bv': batteryVoltage,
        if (solarPower != null) 'sp': solarPower,
        'aal': activeAlarmIds,
        if (aisTargetId != null) 'ais': aisTargetId,
      };

  factory LogContext.fromJson(Map<String, dynamic> json) => LogContext(
        position: json['pos'] != null
            ? GpsPosition.fromJson(json['pos'] as Map<String, dynamic>)
            : null,
        sog: json['sog'] != null ? (json['sog'] as num).toDouble() : null,
        cog: json['cog'] != null ? (json['cog'] as num).toDouble() : null,
        heading:
            json['hdg'] != null ? (json['hdg'] as num).toDouble() : null,
        depth:
            json['dep'] != null ? (json['dep'] as num).toDouble() : null,
        batteryVoltage:
            json['bv'] != null ? (json['bv'] as num).toDouble() : null,
        solarPower:
            json['sp'] != null ? (json['sp'] as num).toDouble() : null,
        activeAlarmIds: (json['aal'] as List<dynamic>).cast<String>(),
        aisTargetId: json['ais'] as String?,
      );
}

class LogEntry {
  final String id;
  final LogEntryType type;
  final String? subtype;
  final DateTime timestamp;
  final String? voyageId;
  final String message;
  final LogContext? context;
  final String? sourceDeviceId;

  const LogEntry({
    required this.id,
    required this.type,
    this.subtype,
    required this.timestamp,
    this.voyageId,
    required this.message,
    this.context,
    this.sourceDeviceId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'tp': type.index,
        if (subtype != null) 'sub': subtype,
        'ts': timestamp.toIso8601String(),
        if (voyageId != null) 'vid': voyageId,
        'msg': message,
        if (context != null) 'ctx': context!.toJson(),
        if (sourceDeviceId != null) 'src': sourceDeviceId,
      };

  factory LogEntry.fromJson(Map<String, dynamic> json) => LogEntry(
        id: json['id'] as String,
        type: LogEntryType.values[json['tp'] as int],
        subtype: json['sub'] as String?,
        timestamp: DateTime.parse(json['ts'] as String),
        voyageId: json['vid'] as String?,
        message: json['msg'] as String,
        context: json['ctx'] != null
            ? LogContext.fromJson(json['ctx'] as Map<String, dynamic>)
            : null,
        sourceDeviceId: json['src'] as String?,
      );
}
