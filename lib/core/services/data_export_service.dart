import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../providers/settings_provider.dart';
import '../providers/voyage_provider.dart';
import '../providers/log_provider.dart';
import '../providers/alarm_provider.dart';
import '../providers/kanban_provider.dart';
import '../providers/task_provider.dart';
import '../providers/issue_provider.dart';
import '../../features/safety/providers/safety_provider.dart';

class DataExportService {
  final Ref _ref;
  DataExportService(this._ref);

  Map<String, dynamic> buildExportMap() {
    final settings  = _ref.read(settingsProvider);
    final safety    = _ref.read(safetyProvider);
    final kanban    = _ref.read(kanbanProvider);
    final voyages   = _ref.read(voyageProvider);
    final logs      = _ref.read(logProvider);
    final alarms    = _ref.read(alarmProvider);
    final taskState = _ref.read(taskProvider);
    final issues    = _ref.read(issueProvider);

    return {
      'version':    1,
      'exportedAt': DateTime.now().toIso8601String(),
      'settings': {
        'vesselName':          settings.vesselName,
        'signalKHost':         settings.signalKHost,
        'signalKPort':         settings.signalKPort,
        'signalKUsername':     settings.signalKUsername,
        'signalKPassword':     settings.signalKPassword,
        'signalKUrl':          settings.signalKUrl,
        'deviceRole':          settings.deviceRole.name,
        'hostIp':              settings.hostIp,
        'hostPort':            settings.hostPort,
        'autoConnectSignalK':  settings.autoConnectSignalK,
        'autoConnectLan':      settings.autoConnectLan,
        'keepScreenOn':        settings.keepScreenOn,
        'tileOrder':           settings.tileOrder,
      },
      'safety': {
        'depthAlarmEnabled':   safety.depthAlarmEnabled,
        'depthAlarmThreshold': safety.depthAlarmThreshold,
        'speedAlarmEnabled':   safety.speedAlarmEnabled,
        'speedAlarmThreshold': safety.speedAlarmThreshold,
      },
      'kanban': {
        'columns': kanban.columns.map((c) => c.toJson()).toList(),
        'cards':   kanban.cards.map((c) => c.toJson()).toList(),
      },
      'voyages': [
        if (voyages.active != null) voyages.active!.toJson(),
        ...voyages.history.map((v) => v.toJson()),
      ],
      'logs':           logs.map((l) => l.toJson()).toList(),
      'alarms':         alarms.map((a) => a.toJson()).toList(),
      'taskTemplates':  taskState.templates.map((t) => t.toJson()).toList(),
      'taskInstances':  taskState.instances.map((i) => i.toJson()).toList(),
      'issues':         issues.map((i) => i.toJson()).toList(),
    };
  }

  /// Write export to a file and share it via the OS share sheet.
  Future<void> exportAndShare() async {
    final data = buildExportMap();
    final json = const JsonEncoder.withIndent('  ').convert(data);
    final now  = DateTime.now();
    final fname =
        'yokuli_backup_${now.year}${_z(now.month)}${_z(now.day)}_${_z(now.hour)}${_z(now.minute)}.json';

    if (kIsWeb) {
      // Web: not supported via share_plus file sharing
      throw UnsupportedError('Export to file not supported on web. Copy the JSON manually.');
    }

    final dir  = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$fname');
    await file.writeAsString(json);
    await Share.shareXFiles([XFile(file.path)], text: 'Yokuli backup – $fname');
  }

  /// Returns the raw export JSON string (usable for copy-paste on web).
  String exportAsJsonString() =>
      const JsonEncoder.withIndent('  ').convert(buildExportMap());

  /// Apply imported data from a JSON string to all providers.
  Future<void> importFromJsonString(String jsonStr) async {
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    await _applyImport(data);
  }

  Future<void> _applyImport(Map<String, dynamic> data) async {
    // Settings
    final s = data['settings'] as Map<String, dynamic>?;
    if (s != null) {
      final cur = _ref.read(settingsProvider);
      await _ref.read(settingsProvider.notifier).update(cur.copyWith(
        vesselName:         s['vesselName']         as String? ?? cur.vesselName,
        signalKHost:        s['signalKHost']         as String? ?? cur.signalKHost,
        signalKPort:        s['signalKPort']         as int?    ?? cur.signalKPort,
        signalKUsername:    s['signalKUsername']     as String? ?? cur.signalKUsername,
        signalKPassword:    s['signalKPassword']     as String? ?? cur.signalKPassword,
        signalKUrl:         s['signalKUrl']          as String? ?? cur.signalKUrl,
        deviceRole: DeviceRole.values.firstWhere(
          (r) => r.name == s['deviceRole'],
          orElse: () => cur.deviceRole,
        ),
        hostIp:             s['hostIp']              as String? ?? cur.hostIp,
        hostPort:           s['hostPort']            as int?    ?? cur.hostPort,
        autoConnectSignalK: s['autoConnectSignalK']  as bool?   ?? cur.autoConnectSignalK,
        autoConnectLan:     s['autoConnectLan']      as bool?   ?? cur.autoConnectLan,
        keepScreenOn:       s['keepScreenOn']        as bool?   ?? cur.keepScreenOn,
        tileOrder: (s['tileOrder'] as List<dynamic>?)?.cast<String>() ?? cur.tileOrder,
      ));
    }

    // Safety
    final sf = data['safety'] as Map<String, dynamic>?;
    if (sf != null) {
      _ref.read(safetyProvider.notifier).setDepthAlarm(
        enabled:   sf['depthAlarmEnabled']   as bool?  ?? false,
        threshold: (sf['depthAlarmThreshold'] as num?)?.toDouble(),
      );
      _ref.read(safetyProvider.notifier).setSpeedAlarm(
        enabled:   sf['speedAlarmEnabled']   as bool?  ?? false,
        threshold: (sf['speedAlarmThreshold'] as num?)?.toDouble(),
      );
    }

    // Kanban
    final k = data['kanban'] as Map<String, dynamic>?;
    if (k != null) await _ref.read(kanbanProvider.notifier).importAll(k);

    // Voyages
    final vs = (data['voyages'] as List?)?.cast<Map<String, dynamic>>();
    if (vs != null) await _ref.read(voyageProvider.notifier).importAll(vs);

    // Logs
    final ls = (data['logs'] as List?)?.cast<Map<String, dynamic>>();
    if (ls != null) await _ref.read(logProvider.notifier).importAll(ls);

    // Alarms
    final as_ = (data['alarms'] as List?)?.cast<Map<String, dynamic>>();
    if (as_ != null) await _ref.read(alarmProvider.notifier).importAll(as_);

    // Tasks
    final tt = (data['taskTemplates'] as List?)?.cast<Map<String, dynamic>>();
    final ti = (data['taskInstances'] as List?)?.cast<Map<String, dynamic>>();
    if (tt != null || ti != null) {
      await _ref.read(taskProvider.notifier).importAll(
        templates: tt ?? [],
        instances: ti ?? [],
      );
    }

    // Issues
    final is_ = (data['issues'] as List?)?.cast<Map<String, dynamic>>();
    if (is_ != null) await _ref.read(issueProvider.notifier).importAll(is_);
  }

  String _z(int n) => n.toString().padLeft(2, '0');
}

final dataExportServiceProvider = Provider<DataExportService>((ref) {
  return DataExportService(ref);
});
