/// Maintenance task status
enum MaintenanceStatus { pending, overdue, completed }

/// Recurrence interval type
enum RecurrenceType { none, days, months, engineHours }

class MaintenanceRecord {
  final String id;
  final String title;
  final String description;
  final String systemCategory; // e.g. "Engine", "Electrical", "Hull", "Safety"
  final DateTime? lastDoneDate;
  final double? lastDoneEngineHours;
  final RecurrenceType recurrenceType;
  final int? recurrenceValue; // e.g. 90 (days) or 250 (hours)
  final MaintenanceStatus status;
  final String notes;

  const MaintenanceRecord({
    required this.id,
    required this.title,
    this.description = '',
    this.systemCategory = 'General',
    this.lastDoneDate,
    this.lastDoneEngineHours,
    this.recurrenceType = RecurrenceType.none,
    this.recurrenceValue,
    this.status = MaintenanceStatus.pending,
    this.notes = '',
  });

  /// Next due date (if recurrence by days)
  DateTime? get nextDueDate {
    if (recurrenceType != RecurrenceType.days) return null;
    if (lastDoneDate == null || recurrenceValue == null) return null;
    return lastDoneDate!.add(Duration(days: recurrenceValue!));
  }

  /// Next due engine hours (if recurrence by engine hours)
  double? get nextDueEngineHours {
    if (recurrenceType != RecurrenceType.engineHours) return null;
    if (lastDoneEngineHours == null || recurrenceValue == null) return null;
    return lastDoneEngineHours! + recurrenceValue!;
  }

  MaintenanceRecord copyWith({
    String? id,
    String? title,
    String? description,
    String? systemCategory,
    DateTime? lastDoneDate,
    double? lastDoneEngineHours,
    RecurrenceType? recurrenceType,
    int? recurrenceValue,
    MaintenanceStatus? status,
    String? notes,
  }) =>
      MaintenanceRecord(
        id: id ?? this.id,
        title: title ?? this.title,
        description: description ?? this.description,
        systemCategory: systemCategory ?? this.systemCategory,
        lastDoneDate: lastDoneDate ?? this.lastDoneDate,
        lastDoneEngineHours: lastDoneEngineHours ?? this.lastDoneEngineHours,
        recurrenceType: recurrenceType ?? this.recurrenceType,
        recurrenceValue: recurrenceValue ?? this.recurrenceValue,
        status: status ?? this.status,
        notes: notes ?? this.notes,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'desc': description,
        'cat': systemCategory,
        if (lastDoneDate != null) 'ldd': lastDoneDate!.toIso8601String(),
        if (lastDoneEngineHours != null) 'ldeh': lastDoneEngineHours,
        'rt': recurrenceType.name,
        if (recurrenceValue != null) 'rv': recurrenceValue,
        'status': status.name,
        'notes': notes,
      };

  factory MaintenanceRecord.fromMap(Map<dynamic, dynamic> map) => MaintenanceRecord(
        id: map['id'] as String,
        title: map['title'] as String,
        description: (map['desc'] as String?) ?? '',
        systemCategory: (map['cat'] as String?) ?? 'General',
        lastDoneDate: map['ldd'] != null ? DateTime.parse(map['ldd'] as String) : null,
        lastDoneEngineHours:
            map['ldeh'] != null ? (map['ldeh'] as num).toDouble() : null,
        recurrenceType: RecurrenceType.values.firstWhere(
          (e) => e.name == map['rt'],
          orElse: () => RecurrenceType.none,
        ),
        recurrenceValue: map['rv'] as int?,
        status: MaintenanceStatus.values.firstWhere(
          (e) => e.name == map['status'],
          orElse: () => MaintenanceStatus.pending,
        ),
        notes: (map['notes'] as String?) ?? '',
      );
}
