class KanbanColumn {
  final String id;
  final String title;
  final int order;

  const KanbanColumn({
    required this.id,
    required this.title,
    required this.order,
  });

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'order': order};

  factory KanbanColumn.fromJson(Map<String, dynamic> j) => KanbanColumn(
        id: j['id'] as String,
        title: j['title'] as String,
        order: (j['order'] as num).toInt(),
      );

  KanbanColumn copyWith({String? title, int? order}) =>
      KanbanColumn(id: id, title: title ?? this.title, order: order ?? this.order);
}

enum KanbanPriority { low, medium, high }

const kKanbanDefaultCategories = <String>[
  '发动机', '电气', '船体', '帆具', '索具', '安全', '其他',
];

const kKanbanDefaultColumns = <KanbanColumn>[
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
  final DateTime? updatedAt;
  final bool archived;

  const KanbanCard({
    required this.id,
    required this.columnId,
    required this.title,
    this.description,
    this.category = '其他',
    this.priority = KanbanPriority.medium,
    required this.createdAt,
    this.updatedAt,
    this.archived = false,
  });

  KanbanCard copyWith({
    String? columnId,
    String? title,
    String? description,
    String? category,
    KanbanPriority? priority,
    DateTime? updatedAt,
    bool? archived,
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
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'col': columnId,
        'title': title,
        if (description != null) 'desc': description,
        'cat': category,
        'pri': priority.index,
        'ca': createdAt.toIso8601String(),
        if (updatedAt != null) 'ua': updatedAt!.toIso8601String(),
        if (archived) 'arc': true,
      };

  factory KanbanCard.fromJson(Map<String, dynamic> j) => KanbanCard(
        id: j['id'] as String,
        columnId: j['col'] as String,
        title: j['title'] as String,
        description: j['desc'] as String?,
        category: j['cat'] as String? ?? '其他',
        priority: KanbanPriority.values[(j['pri'] as num?)?.toInt() ?? 1],
        createdAt: DateTime.parse(j['ca'] as String),
        updatedAt: j['ua'] != null ? DateTime.parse(j['ua'] as String) : null,
        archived: j['arc'] as bool? ?? false,
      );
}

class KanbanState {
  final List<KanbanColumn> columns;
  final List<KanbanCard> cards;

  const KanbanState({
    this.columns = const [],
    this.cards = const [],
  });

  List<KanbanCard> cardsForColumn(String columnId, {String? category}) =>
      cards
          .where((c) =>
              c.columnId == columnId &&
              !c.archived &&
              (category == null || c.category == category))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  List<KanbanCard> get archivedCards =>
      cards.where((c) => c.archived).toList()
        ..sort((a, b) => (b.updatedAt ?? b.createdAt)
            .compareTo(a.updatedAt ?? a.createdAt));
}
