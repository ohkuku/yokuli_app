import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/providers/issue_provider.dart';
import '../../../core/models/issue.dart';

class IssuesScreen extends ConsumerStatefulWidget {
  const IssuesScreen({super.key});

  @override
  ConsumerState<IssuesScreen> createState() => _IssuesScreenState();
}

class _IssuesScreenState extends ConsumerState<IssuesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showCreateDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => _CreateIssueDialog(
        onCreate: (title, severity) async {
          await ref.read(issueProvider.notifier).create(
                title: title,
                source: IssueSource.manual,
                severity: severity,
              );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          title: const Text('Issues',
              style: TextStyle(color: AppColors.textPrimary)),
          iconTheme: const IconThemeData(color: AppColors.textPrimary),
          bottom: const TabBar(
            labelColor: AppColors.cyan,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.cyan,
            tabs: [
              Tab(text: 'Open'),
              Tab(text: 'Resolved'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          backgroundColor: AppColors.cyan,
          foregroundColor: AppColors.background,
          onPressed: _showCreateDialog,
          child: const Icon(Icons.add_rounded),
        ),
        body: const TabBarView(
          children: [
            _OpenTab(),
            _ResolvedTab(),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Open Tab
// ---------------------------------------------------------------------------

class _OpenTab extends ConsumerWidget {
  const _OpenTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final issues = ref
        .watch(issueProvider)
        .where((t) => t.isOpen)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (issues.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_outline_rounded,
                  size: 60, color: AppColors.success),
              SizedBox(height: 16),
              Text(
                'No open issues',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 8),
              Text(
                'All clear — tap + to log a new issue.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      itemCount: issues.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final issue = issues[index];
        return _IssueCard(
          ticket: issue,
          onTap: () => _showDetail(context, issue.id, ref),
        );
      },
    );
  }

  void _showDetail(BuildContext context, String issueId, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _IssueDetailSheet(issueId: issueId),
    );
  }
}

// ---------------------------------------------------------------------------
// Resolved Tab
// ---------------------------------------------------------------------------

class _ResolvedTab extends ConsumerWidget {
  const _ResolvedTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final issues = ref
        .watch(issueProvider)
        .where((t) => !t.isOpen)
        .toList()
      ..sort((a, b) {
        final ra = a.resolvedAt ?? a.createdAt;
        final rb = b.resolvedAt ?? b.createdAt;
        return rb.compareTo(ra);
      });

    if (issues.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.history_rounded,
                  size: 60, color: AppColors.inactive),
              SizedBox(height: 16),
              Text(
                'No resolved issues yet',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      itemCount: issues.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final issue = issues[index];
        return _IssueCard(
          ticket: issue,
          onTap: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => _IssueDetailSheet(issueId: issue.id),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Issue Card
// ---------------------------------------------------------------------------

class _IssueCard extends StatelessWidget {
  final IssueTicket ticket;
  final VoidCallback onTap;

  const _IssueCard({required this.ticket, required this.onTap});

  static const _severityColors = {
    IssueSeverity.high: AppColors.danger,
    IssueSeverity.medium: AppColors.warning,
    IssueSeverity.low: AppColors.success,
  };

  @override
  Widget build(BuildContext context) {
    final sevColor =
        _severityColors[ticket.severity] ?? AppColors.inactive;
    final dateFmt =
        DateFormat('dd MMM yyyy HH:mm').format(ticket.createdAt.toLocal());

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Severity dot
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: sevColor,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ticket.title,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _StatusChip(status: ticket.status),
                      const SizedBox(width: 8),
                      _SourceChip(source: ticket.source),
                    ],
                  ),
                ],
              ),
            ),
            // Date
            Text(
              dateFmt,
              style: const TextStyle(
                  color: AppColors.textMuted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Issue Detail Bottom Sheet
// ---------------------------------------------------------------------------

class _IssueDetailSheet extends ConsumerWidget {
  final String issueId;
  const _IssueDetailSheet({required this.issueId});

  static const _severityColors = {
    IssueSeverity.high: AppColors.danger,
    IssueSeverity.medium: AppColors.warning,
    IssueSeverity.low: AppColors.success,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticket = ref
        .watch(issueProvider)
        .cast<IssueTicket?>()
        .firstWhere((t) => t?.id == issueId, orElse: () => null);

    if (ticket == null) {
      return const SizedBox.shrink();
    }

    final sevColor =
        _severityColors[ticket.severity] ?? AppColors.inactive;
    final dateFmt =
        DateFormat('dd MMM yyyy HH:mm').format(ticket.createdAt.toLocal());

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      minChildSize: 0.35,
      builder: (ctx, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(top: 5),
                    decoration: BoxDecoration(
                      color: sevColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      ticket.title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Meta row
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: Row(
                children: [
                  _SourceChip(source: ticket.source),
                  const SizedBox(width: 8),
                  _StatusChip(status: ticket.status),
                  const Spacer(),
                  Text(
                    dateFmt,
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Divider(color: AppColors.border, height: 1),
            // Scrollable body
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.all(20),
                children: [
                  // Status buttons
                  const Text(
                    'STATUS',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _StatusButtonRow(
                    current: ticket.status,
                    onSelect: (s) => ref
                        .read(issueProvider.notifier)
                        .updateStatus(issueId, s),
                  ),
                  const SizedBox(height: 20),

                  // Notes
                  Row(
                    children: [
                      const Text(
                        'NOTES',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () =>
                            _showAddNote(context, ref, issueId),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.teal.withAlpha(22),
                            borderRadius: BorderRadius.circular(7),
                            border: Border.all(
                                color: AppColors.teal.withAlpha(80)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add_rounded,
                                  size: 14, color: AppColors.teal),
                              SizedBox(width: 4),
                              Text(
                                'Add Note',
                                style: TextStyle(
                                  color: AppColors.teal,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (ticket.notes.isEmpty)
                    const Text(
                      'No notes yet.',
                      style: TextStyle(
                          color: AppColors.textMuted, fontSize: 13),
                    )
                  else
                    ...ticket.notes.map(
                      (note) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text(
                          note,
                          style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddNote(
      BuildContext context, WidgetRef ref, String issueId) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        title: const Text('Add Note',
            style: TextStyle(color: AppColors.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(
            hintText: 'Enter note…',
            hintStyle: TextStyle(color: AppColors.textMuted),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.border),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.cyan),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Add',
                style: TextStyle(color: AppColors.cyan)),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      await ref.read(issueProvider.notifier).addNote(issueId, result);
    }
  }
}

// ---------------------------------------------------------------------------
// Status Button Row
// ---------------------------------------------------------------------------

class _StatusButtonRow extends StatelessWidget {
  final IssueStatus current;
  final void Function(IssueStatus) onSelect;

  const _StatusButtonRow({
    required this.current,
    required this.onSelect,
  });

  static const _entries = [
    (IssueStatus.open, 'Open', AppColors.inactive),
    (IssueStatus.doing, 'In Progress', AppColors.cyan),
    (IssueStatus.blocked, 'Blocked', AppColors.danger),
    (IssueStatus.done, 'Resolved', AppColors.success),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _entries.map((entry) {
        final (status, label, color) = entry;
        final isSelected = current == status;
        return GestureDetector(
          onTap: () => onSelect(status),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: isSelected ? color.withAlpha(40) : color.withAlpha(12),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: isSelected
                    ? color.withAlpha(180)
                    : color.withAlpha(50),
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? color : color.withAlpha(160),
                fontSize: 13,
                fontWeight: isSelected
                    ? FontWeight.w700
                    : FontWeight.w500,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Create Issue Dialog
// ---------------------------------------------------------------------------

class _CreateIssueDialog extends StatefulWidget {
  final Future<void> Function(String title, IssueSeverity severity) onCreate;

  const _CreateIssueDialog({required this.onCreate});

  @override
  State<_CreateIssueDialog> createState() => _CreateIssueDialogState();
}

class _CreateIssueDialogState extends State<_CreateIssueDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  IssueSeverity _severity = IssueSeverity.medium;
  bool _loading = false;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _loading = true);
    await widget.onCreate(
        _titleController.text.trim(), _severity);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.cardBg,
      title: const Text('New Issue',
          style: TextStyle(color: AppColors.textPrimary)),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _titleController,
              autofocus: true,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Issue title',
                labelStyle: TextStyle(color: AppColors.textMuted),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.border),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.cyan),
                ),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            const Text(
              'SEVERITY',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _SeverityButton(
                  label: 'Low',
                  color: AppColors.success,
                  selected: _severity == IssueSeverity.low,
                  onTap: () =>
                      setState(() => _severity = IssueSeverity.low),
                ),
                const SizedBox(width: 8),
                _SeverityButton(
                  label: 'Medium',
                  color: AppColors.warning,
                  selected: _severity == IssueSeverity.medium,
                  onTap: () =>
                      setState(() => _severity = IssueSeverity.medium),
                ),
                const SizedBox(width: 8),
                _SeverityButton(
                  label: 'High',
                  color: AppColors.danger,
                  selected: _severity == IssueSeverity.high,
                  onTap: () =>
                      setState(() => _severity = IssueSeverity.high),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text('Cancel',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.cyan,
            foregroundColor: AppColors.background,
          ),
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.background,
                  ),
                )
              : const Text('Create',
                  style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

class _SeverityButton extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _SeverityButton({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color.withAlpha(40) : color.withAlpha(12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? color.withAlpha(180)
                : color.withAlpha(60),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? color : color.withAlpha(160),
            fontSize: 13,
            fontWeight:
                selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Status Chip
// ---------------------------------------------------------------------------

class _StatusChip extends StatelessWidget {
  final IssueStatus status;
  const _StatusChip({required this.status});

  static const _labels = {
    IssueStatus.open: 'Open',
    IssueStatus.doing: 'In Progress',
    IssueStatus.blocked: 'Blocked',
    IssueStatus.done: 'Resolved',
  };

  static const _colors = {
    IssueStatus.open: AppColors.inactive,
    IssueStatus.doing: AppColors.cyan,
    IssueStatus.blocked: AppColors.danger,
    IssueStatus.done: AppColors.success,
  };

  @override
  Widget build(BuildContext context) {
    final label = _labels[status] ?? status.name;
    final color = _colors[status] ?? AppColors.inactive;
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Source Chip
// ---------------------------------------------------------------------------

class _SourceChip extends StatelessWidget {
  final IssueSource source;
  const _SourceChip({required this.source});

  static const _labels = {
    IssueSource.checklist: 'Checklist',
    IssueSource.manual: 'Manual',
    IssueSource.alarm: 'Alarm',
  };

  @override
  Widget build(BuildContext context) {
    final label = _labels[source] ?? source.name;
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.textMuted.withAlpha(20),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.textMuted.withAlpha(50)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
