enum TaskCategory { preDeparture, postArrival, periodic, safety, custom }

enum TaskRecurrence { none, daily, weekly, monthly, perVoyage }

enum TaskStatus { open, inProgress, done, skipped }

enum ChecklistItemStatus { pending, done, issue }

// ---------------------------------------------------------------------------

class TaskChecklistItemTemplate {
  final String id;
  final String title;

  const TaskChecklistItemTemplate({
    required this.id,
    required this.title,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        't': title,
      };

  factory TaskChecklistItemTemplate.fromJson(Map<String, dynamic> json) {
    return TaskChecklistItemTemplate(
      id: json['id'] as String,
      title: json['t'] as String,
    );
  }
}

// ---------------------------------------------------------------------------

class TaskChecklistItem {
  final String id;
  final String title;
  final ChecklistItemStatus status;
  final String? note;
  final String? createdIssueId;

  const TaskChecklistItem({
    required this.id,
    required this.title,
    required this.status,
    this.note,
    this.createdIssueId,
  });

  TaskChecklistItem copyWith({
    String? id,
    String? title,
    ChecklistItemStatus? status,
    Object? note = _sentinel,
    Object? createdIssueId = _sentinel,
  }) {
    return TaskChecklistItem(
      id: id ?? this.id,
      title: title ?? this.title,
      status: status ?? this.status,
      note: note == _sentinel ? this.note : note as String?,
      createdIssueId: createdIssueId == _sentinel
          ? this.createdIssueId
          : createdIssueId as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        't': title,
        's': status.index,
        if (note != null) 'n': note,
        if (createdIssueId != null) 'ci': createdIssueId,
      };

  factory TaskChecklistItem.fromJson(Map<String, dynamic> json) {
    return TaskChecklistItem(
      id: json['id'] as String,
      title: json['t'] as String,
      status: ChecklistItemStatus.values[json['s'] as int],
      note: json['n'] as String?,
      createdIssueId: json['ci'] as String?,
    );
  }
}

// ---------------------------------------------------------------------------

class TaskTemplate {
  final String id;
  final String title;
  final TaskCategory category;
  final TaskRecurrence recurrence;
  final List<TaskChecklistItemTemplate> checklistItems;
  final DateTime createdAt;
  final bool isBuiltIn;

  const TaskTemplate({
    required this.id,
    required this.title,
    required this.category,
    required this.recurrence,
    required this.checklistItems,
    required this.createdAt,
    this.isBuiltIn = false,
  });

  static List<TaskTemplate> get builtInTemplates => [
        TaskTemplate(
          id: 'builtin_predep',
          title: 'Pre-Departure',
          category: TaskCategory.preDeparture,
          recurrence: TaskRecurrence.perVoyage,
          isBuiltIn: true,
          createdAt: DateTime.utc(2024, 1, 1),
          checklistItems: [
            TaskChecklistItemTemplate(
                id: 'predep_01', title: 'Bilge check'),
            TaskChecklistItemTemplate(
                id: 'predep_02', title: 'Engine room visual inspection'),
            TaskChecklistItemTemplate(
                id: 'predep_03', title: 'Battery status'),
            TaskChecklistItemTemplate(
                id: 'predep_04', title: 'Signal K online'),
            TaskChecklistItemTemplate(
                id: 'predep_05', title: 'GPS / AIS / VHF check'),
            TaskChecklistItemTemplate(
                id: 'predep_06', title: 'Anchor ready'),
            TaskChecklistItemTemplate(
                id: 'predep_07', title: 'Seacock state'),
          ],
        ),
        TaskTemplate(
          id: 'builtin_postarr',
          title: 'Post-Arrival',
          category: TaskCategory.postArrival,
          recurrence: TaskRecurrence.perVoyage,
          isBuiltIn: true,
          createdAt: DateTime.utc(2024, 1, 1),
          checklistItems: [
            TaskChecklistItemTemplate(
                id: 'postarr_01', title: 'Engine stop confirmed'),
            TaskChecklistItemTemplate(
                id: 'postarr_02', title: 'Shore / anchor state'),
            TaskChecklistItemTemplate(
                id: 'postarr_03', title: 'Bilge check'),
            TaskChecklistItemTemplate(
                id: 'postarr_04', title: 'Power mode check'),
            TaskChecklistItemTemplate(
                id: 'postarr_05', title: 'Write anomalies'),
            TaskChecklistItemTemplate(
                id: 'postarr_06', title: 'Secure deck'),
          ],
        ),
      ];

  Map<String, dynamic> toJson() => {
        'id': id,
        't': title,
        'cat': category.index,
        'rec': recurrence.index,
        'cl': checklistItems.map((i) => i.toJson()).toList(),
        'ca': createdAt.toIso8601String(),
        'bi': isBuiltIn,
      };

  factory TaskTemplate.fromJson(Map<String, dynamic> json) {
    return TaskTemplate(
      id: json['id'] as String,
      title: json['t'] as String,
      category: TaskCategory.values[json['cat'] as int],
      recurrence: TaskRecurrence.values[json['rec'] as int],
      checklistItems: (json['cl'] as List<dynamic>)
          .map((e) =>
              TaskChecklistItemTemplate.fromJson(e as Map<String, dynamic>))
          .toList(),
      createdAt: DateTime.parse(json['ca'] as String),
      isBuiltIn: json['bi'] as bool? ?? false,
    );
  }
}

// ---------------------------------------------------------------------------

class TaskInstance {
  final String id;
  final String templateId;
  final String? voyageId;
  final TaskStatus status;
  final List<TaskChecklistItem> checklistItems;
  final DateTime createdAt;
  final DateTime? completedAt;
  final String? sourceDeviceId;
  // LWW sync fields
  final DateTime updatedAt;
  final bool deleted;

  TaskInstance({
    required this.id,
    required this.templateId,
    this.voyageId,
    required this.status,
    required this.checklistItems,
    required this.createdAt,
    this.completedAt,
    this.sourceDeviceId,
    DateTime? updatedAt,
    this.deleted = false,
  }) : updatedAt = updatedAt ?? createdAt;

  double get progress {
    if (checklistItems.isEmpty) return 0.0;
    final doneCount =
        checklistItems.where((i) => i.status == ChecklistItemStatus.done).length;
    return doneCount / checklistItems.length;
  }

  TaskInstance copyWith({
    String? id,
    String? templateId,
    Object? voyageId = _sentinel,
    TaskStatus? status,
    List<TaskChecklistItem>? checklistItems,
    DateTime? createdAt,
    Object? completedAt = _sentinel,
    Object? sourceDeviceId = _sentinel,
    DateTime? updatedAt,
    bool? deleted,
  }) {
    return TaskInstance(
      id: id ?? this.id,
      templateId: templateId ?? this.templateId,
      voyageId: voyageId == _sentinel ? this.voyageId : voyageId as String?,
      status: status ?? this.status,
      checklistItems: checklistItems ?? this.checklistItems,
      createdAt: createdAt ?? this.createdAt,
      completedAt:
          completedAt == _sentinel ? this.completedAt : completedAt as DateTime?,
      sourceDeviceId: sourceDeviceId == _sentinel
          ? this.sourceDeviceId
          : sourceDeviceId as String?,
      updatedAt: updatedAt ?? this.updatedAt,
      deleted: deleted ?? this.deleted,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'tid': templateId,
        if (voyageId != null) 'vid': voyageId,
        's': status.index,
        'cl': checklistItems.map((i) => i.toJson()).toList(),
        'ca': createdAt.toIso8601String(),
        if (completedAt != null) 'coa': completedAt!.toIso8601String(),
        // Use 'src' key (migrated from legacy 'sd')
        if (sourceDeviceId != null) 'src': sourceDeviceId,
        'ua': updatedAt.toIso8601String(),
        if (deleted) 'del': true,
      };

  factory TaskInstance.fromJson(Map<String, dynamic> json) {
    final createdAt = DateTime.parse(json['ca'] as String);
    return TaskInstance(
      id: json['id'] as String,
      templateId: json['tid'] as String,
      voyageId: json['vid'] as String?,
      status: TaskStatus.values[json['s'] as int],
      checklistItems: (json['cl'] as List<dynamic>)
          .map((e) => TaskChecklistItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      createdAt: createdAt,
      completedAt: json['coa'] != null
          ? DateTime.parse(json['coa'] as String)
          : null,
      // Read 'src' (new key), fall back to legacy 'sd'
      sourceDeviceId: (json['src'] ?? json['sd']) as String?,
      updatedAt: json['ua'] != null
          ? DateTime.parse(json['ua'] as String)
          : createdAt,
      deleted: json['del'] as bool? ?? false,
    );
  }
}

// Sentinel object used for nullable copyWith pattern
const Object _sentinel = Object();
