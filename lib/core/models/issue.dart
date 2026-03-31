enum IssueSource { checklist, manual, alarm }

enum IssueSeverity { low, medium, high }

enum IssueStatus { open, doing, blocked, done }

class IssueTicket {
  final String id;
  final String title;
  final IssueSource source;
  final IssueSeverity severity;
  final IssueStatus status;
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final List<String> notes;
  final List<String> linkedLogIds;
  final String? linkedVoyageId;
  // LWW sync fields
  final DateTime updatedAt;
  final bool deleted;
  final String? sourceDeviceId; // key 'sdid' — 'src' is taken by IssueSource

  IssueTicket({
    required this.id,
    required this.title,
    required this.source,
    required this.severity,
    required this.status,
    required this.createdAt,
    this.resolvedAt,
    required this.notes,
    required this.linkedLogIds,
    this.linkedVoyageId,
    DateTime? updatedAt,
    this.deleted = false,
    this.sourceDeviceId,
  }) : updatedAt = updatedAt ?? createdAt;

  bool get isOpen => status != IssueStatus.done;

  IssueTicket copyWith({
    String? id,
    String? title,
    IssueSource? source,
    IssueSeverity? severity,
    IssueStatus? status,
    DateTime? createdAt,
    Object? resolvedAt = _sentinel,
    List<String>? notes,
    List<String>? linkedLogIds,
    Object? linkedVoyageId = _sentinel,
    DateTime? updatedAt,
    bool? deleted,
    Object? sourceDeviceId = _sentinel,
  }) {
    return IssueTicket(
      id: id ?? this.id,
      title: title ?? this.title,
      source: source ?? this.source,
      severity: severity ?? this.severity,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      resolvedAt:
          resolvedAt == _sentinel ? this.resolvedAt : resolvedAt as DateTime?,
      notes: notes ?? this.notes,
      linkedLogIds: linkedLogIds ?? this.linkedLogIds,
      linkedVoyageId: linkedVoyageId == _sentinel
          ? this.linkedVoyageId
          : linkedVoyageId as String?,
      updatedAt: updatedAt ?? this.updatedAt,
      deleted: deleted ?? this.deleted,
      sourceDeviceId: sourceDeviceId == _sentinel
          ? this.sourceDeviceId
          : sourceDeviceId as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        't': title,
        'src': source.index,
        'sev': severity.index,
        's': status.index,
        'ca': createdAt.toIso8601String(),
        if (resolvedAt != null) 'ra': resolvedAt!.toIso8601String(),
        'n': notes,
        'll': linkedLogIds,
        if (linkedVoyageId != null) 'lv': linkedVoyageId,
        'ua': updatedAt.toIso8601String(),
        if (deleted) 'del': true,
        if (sourceDeviceId != null) 'sdid': sourceDeviceId,
      };

  factory IssueTicket.fromJson(Map<String, dynamic> json) {
    final createdAt = DateTime.parse(json['ca'] as String);
    return IssueTicket(
      id: json['id'] as String,
      title: json['t'] as String,
      source: IssueSource.values[json['src'] as int],
      severity: IssueSeverity.values[json['sev'] as int],
      status: IssueStatus.values[json['s'] as int],
      createdAt: createdAt,
      resolvedAt:
          json['ra'] != null ? DateTime.parse(json['ra'] as String) : null,
      notes: (json['n'] as List<dynamic>).cast<String>(),
      linkedLogIds: (json['ll'] as List<dynamic>).cast<String>(),
      linkedVoyageId: json['lv'] as String?,
      updatedAt: json['ua'] != null
          ? DateTime.parse(json['ua'] as String)
          : createdAt,
      deleted: json['del'] as bool? ?? false,
      sourceDeviceId: json['sdid'] as String?,
    );
  }
}

// Sentinel object used for nullable copyWith pattern
const Object _sentinel = Object();
