import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../models/task.dart';
import '../utils/id_gen.dart';
import 'device_provider.dart';
import 'lan_broadcast.dart';

// ---------------------------------------------------------------------------
// _JsonStore — private file-based JSON persistence helper
// ---------------------------------------------------------------------------

class _JsonStore {
  static Future<File> _file(String name) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/yokuli_$name.json');
  }

  static Future<List<Map<String, dynamic>>> load(String name) async {
    try {
      final f = await _file(name);
      if (!await f.exists()) return [];
      final data = jsonDecode(await f.readAsString());
      return List<Map<String, dynamic>>.from(data as List);
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(
      String name, List<Map<String, dynamic>> data) async {
    try {
      (await _file(name)).writeAsString(jsonEncode(data));
    } catch (_) {}
  }
}

// ---------------------------------------------------------------------------
// TaskState
// ---------------------------------------------------------------------------

class TaskState {
  final List<TaskTemplate> templates;
  final List<TaskInstance> instances;

  const TaskState({
    required this.templates,
    required this.instances,
  });

  /// Instances that are neither done nor skipped, and not deleted.
  List<TaskInstance> get openInstances =>
      instances.where((i) => i.status != TaskStatus.done &&
          i.status != TaskStatus.skipped && !i.deleted).toList();
}

// ---------------------------------------------------------------------------
// TaskNotifier
// ---------------------------------------------------------------------------

class TaskNotifier extends Notifier<TaskState> {
  static const String _templateStoreName = 'task_templates';
  static const String _instanceStoreName = 'task_instances';

  @override
  TaskState build() => TaskState(
        templates: TaskTemplate.builtInTemplates,
        instances: const [],
      );

  // ---- Persistence --------------------------------------------------------

  /// Load custom templates (non built-in) and all instances from disk.
  Future<void> load() async {
    final templateRows =
        await _JsonStore.load(_templateStoreName);
    final instanceRows =
        await _JsonStore.load(_instanceStoreName);

    final customTemplates =
        templateRows.map(TaskTemplate.fromJson).toList();
    final instances =
        instanceRows.map(TaskInstance.fromJson).toList();

    // Merge: built-ins first, then custom (disk may have updated built-ins
    // if we ever allow editing, but for now just append custom).
    final allTemplates = [
      ...TaskTemplate.builtInTemplates,
      ...customTemplates.where((t) => !t.isBuiltIn),
    ];

    state = TaskState(templates: allTemplates, instances: instances);
  }

  Future<void> save() async {
    // Only persist non-built-in templates to avoid redundancy.
    final customTemplates =
        state.templates.where((t) => !t.isBuiltIn).toList();
    await _JsonStore.save(_templateStoreName,
        customTemplates.map((t) => t.toJson()).toList());
    await _JsonStore.save(_instanceStoreName,
        state.instances.map((i) => i.toJson()).toList());
  }

  Future<void> importAll({
    required List<Map<String, dynamic>> templates,
    required List<Map<String, dynamic>> instances,
  }) async {
    state = TaskState(
      templates: templates.map(TaskTemplate.fromJson).toList(),
      instances: instances.map(TaskInstance.fromJson).toList(),
    );
    await save();
  }

  // ---- Actions ------------------------------------------------------------

  /// Create a new [TaskInstance] from the given [templateId].
  Future<TaskInstance> createInstance(
    String templateId, {
    String? voyageId,
  }) async {
    final template = state.templates.firstWhere(
      (t) => t.id == templateId,
      orElse: () => throw ArgumentError(
          'No template found with id "$templateId"'),
    );

    final now = DateTime.now();
    final deviceId = ref.read(deviceProvider).deviceId;
    final instance = TaskInstance(
      id: generateId(),
      templateId: templateId,
      voyageId: voyageId,
      status: TaskStatus.open,
      checklistItems: template.checklistItems
          .map((tpl) => TaskChecklistItem(
                id: tpl.id,
                title: tpl.title,
                status: ChecklistItemStatus.pending,
              ))
          .toList(),
      createdAt: now,
      updatedAt: now,
      sourceDeviceId: deviceId,
    );

    state = TaskState(
      templates: state.templates,
      instances: [...state.instances, instance],
    );
    await save();
    ref.read(lanBroadcastProvider)?.call(
        {'type': 'task_upsert', 'data': instance.toJson()});
    return instance;
  }

  /// Update a single checklist item within an instance.
  Future<void> updateChecklistItem(
    String instanceId,
    String itemId,
    ChecklistItemStatus status, {
    String? note,
    String? issueId,
  }) async {
    final now = DateTime.now();
    final instances = state.instances.map((inst) {
      if (inst.id != instanceId) return inst;

      final updatedItems = inst.checklistItems.map((item) {
        if (item.id != itemId) return item;
        return item.copyWith(
          status: status,
          note: note ?? item.note,
          createdIssueId: issueId ?? item.createdIssueId,
        );
      }).toList();

      // Auto-advance instance status to inProgress once any item changes.
      final newStatus = inst.status == TaskStatus.open
          ? TaskStatus.inProgress
          : inst.status;

      return inst.copyWith(
        checklistItems: updatedItems,
        status: newStatus,
        updatedAt: now,
      );
    }).toList();

    state = TaskState(templates: state.templates, instances: instances);
    await save();
    final updated = state.instances.firstWhere((i) => i.id == instanceId);
    ref.read(lanBroadcastProvider)?.call(
        {'type': 'task_upsert', 'data': updated.toJson()});
  }

  /// Mark an instance as done and record the completion timestamp.
  Future<void> completeInstance(String instanceId) async {
    final now = DateTime.now();
    final instances = state.instances.map((inst) {
      if (inst.id != instanceId) return inst;
      return inst.copyWith(
        status: TaskStatus.done,
        completedAt: now,
        updatedAt: now,
      );
    }).toList();

    state = TaskState(templates: state.templates, instances: instances);
    await save();
    final updated = state.instances.firstWhere((i) => i.id == instanceId);
    ref.read(lanBroadcastProvider)?.call(
        {'type': 'task_upsert', 'data': updated.toJson()});
  }

  /// Mark an instance as skipped.
  Future<void> skipInstance(String instanceId) async {
    final now = DateTime.now();
    final instances = state.instances.map((inst) {
      if (inst.id != instanceId) return inst;
      return inst.copyWith(status: TaskStatus.skipped, updatedAt: now);
    }).toList();

    state = TaskState(templates: state.templates, instances: instances);
    await save();
    final updated = state.instances.firstWhere((i) => i.id == instanceId);
    ref.read(lanBroadcastProvider)?.call(
        {'type': 'task_upsert', 'data': updated.toJson()});
  }

  /// Upsert a [TaskInstance] received from a remote device (LAN sync).
  /// Per-record LWW: only overwrites if incoming updatedAt is strictly newer.
  Future<void> upsertInstanceRemote(Map<String, dynamic> data) async {
    try {
      final instance = TaskInstance.fromJson(data);
      final idx = state.instances.indexWhere((i) => i.id == instance.id);
      final List<TaskInstance> updated;
      if (idx >= 0) {
        if (!instance.updatedAt.isAfter(state.instances[idx].updatedAt)) return;
        updated = List<TaskInstance>.from(state.instances);
        updated[idx] = instance;
      } else {
        updated = [...state.instances, instance];
      }
      state = TaskState(templates: state.templates, instances: updated);
      await save();
    } catch (_) {}
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final taskProvider =
    NotifierProvider<TaskNotifier, TaskState>(TaskNotifier.new);

/// Convenience: all open (non-done, non-skipped) task instances.
final openTasksProvider = Provider<List<TaskInstance>>(
  (ref) => ref.watch(taskProvider).openInstances,
);
