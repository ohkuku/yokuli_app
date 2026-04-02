class KanbanColumn {
  final String id;
  final String title;
  final int order;
  // LWW sync fields
  final DateTime updatedAt;
  final bool deleted;
  final String? sourceDeviceId;

  KanbanColumn({
    required this.id,
    required this.title,
    required this.order,
    DateTime? updatedAt,
    this.deleted = false,
    this.sourceDeviceId,
  }) : updatedAt = updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'order': order,
        'ua': updatedAt.toIso8601String(),
        if (deleted) 'del': true,
        if (sourceDeviceId != null) 'src': sourceDeviceId,
      };

  factory KanbanColumn.fromJson(Map<String, dynamic> j) => KanbanColumn(
        id: j['id'] as String,
        title: j['title'] as String,
        order: (j['order'] as num).toInt(),
        updatedAt: j['ua'] != null
            ? DateTime.parse(j['ua'] as String)
            : DateTime.fromMillisecondsSinceEpoch(0),
        deleted: j['del'] as bool? ?? false,
        sourceDeviceId: j['src'] as String?,
      );

  KanbanColumn copyWith({
    String? title,
    int? order,
    DateTime? updatedAt,
    bool? deleted,
    Object? sourceDeviceId = _sentinel,
  }) =>
      KanbanColumn(
        id: id,
        title: title ?? this.title,
        order: order ?? this.order,
        updatedAt: updatedAt ?? this.updatedAt,
        deleted: deleted ?? this.deleted,
        sourceDeviceId: sourceDeviceId == _sentinel
            ? this.sourceDeviceId
            : sourceDeviceId as String?,
      );
}

enum KanbanPriority { low, medium, high }

const kKanbanDefaultCategories = <String>[
  '发动机', '电气', '船体', '帆具', '索具', '安全', '其他',
];

final kKanbanDefaultColumns = <KanbanColumn>[
  KanbanColumn(id: 'backlog', title: '待办', order: 0),
  KanbanColumn(id: 'inprogress', title: '进行中', order: 1),
  KanbanColumn(id: 'done', title: '已完成', order: 2),
];

class KanbanCard {
  final String id;
  final String columnId;
  final String title;
  final String? description;
  final String category;
  final KanbanPriority priority;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool archived;
  // LWW sync fields
  final bool deleted;
  final String? sourceDeviceId;

  KanbanCard({
    required this.id,
    required this.columnId,
    required this.title,
    this.description,
    this.category = '其他',
    this.priority = KanbanPriority.medium,
    required this.createdAt,
    DateTime? updatedAt,
    this.archived = false,
    this.deleted = false,
    this.sourceDeviceId,
  }) : updatedAt = updatedAt ?? createdAt;

  KanbanCard copyWith({
    String? columnId,
    String? title,
    String? description,
    String? category,
    KanbanPriority? priority,
    DateTime? updatedAt,
    bool? archived,
    bool? deleted,
    Object? sourceDeviceId = _sentinel,
  }) =>
      KanbanCard(
        id: id,
        columnId: columnId ?? this.columnId,
        title: title ?? this.title,
        description: description ?? this.description,
        category: category ?? this.category,
        priority: priority ?? this.priority,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        archived: archived ?? this.archived,
        deleted: deleted ?? this.deleted,
        sourceDeviceId: sourceDeviceId == _sentinel
            ? this.sourceDeviceId
            : sourceDeviceId as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'col': columnId,
        'title': title,
        if (description != null) 'desc': description,
        'cat': category,
        'pri': priority.index,
        'ca': createdAt.toIso8601String(),
        'ua': updatedAt.toIso8601String(),
        if (archived) 'arc': true,
        if (deleted) 'del': true,
        if (sourceDeviceId != null) 'src': sourceDeviceId,
      };

  factory KanbanCard.fromJson(Map<String, dynamic> j) {
    final createdAt = DateTime.parse(j['ca'] as String);
    return KanbanCard(
      id: j['id'] as String,
      columnId: j['col'] as String,
      title: j['title'] as String,
      description: j['desc'] as String?,
      category: j['cat'] as String? ?? '其他',
      priority: KanbanPriority.values[(j['pri'] as num?)?.toInt() ?? 1],
      createdAt: createdAt,
      updatedAt: j['ua'] != null ? DateTime.parse(j['ua'] as String) : createdAt,
      archived: j['arc'] as bool? ?? false,
      deleted: j['del'] as bool? ?? false,
      sourceDeviceId: j['src'] as String?,
    );
  }
}

class KanbanState {
  final List<KanbanColumn> columns;
  final List<KanbanCard> cards;

  const KanbanState({
    this.columns = const [],
    this.cards = const [],
  });

  List<KanbanCard> cardsForColumn(String columnId,
          {String? category, Set<String>? categories}) =>
      cards
          .where((c) =>
              c.columnId == columnId &&
              !c.archived &&
              !c.deleted &&
              (category == null || c.category == category) &&
              (categories == null ||
                  categories.isEmpty ||
                  categories.contains(c.category)))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  List<KanbanCard> get archivedCards =>
      cards.where((c) => c.archived && !c.deleted).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
}

// Sentinel object used for nullable copyWith pattern
const Object _sentinel = Object();
