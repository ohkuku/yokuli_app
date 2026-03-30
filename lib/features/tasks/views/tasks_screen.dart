import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/providers/task_provider.dart';
import '../../../core/providers/issue_provider.dart';
import '../../../core/models/task.dart';
import '../../../core/models/issue.dart';

class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen>
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

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          title: const Text('Tasks',
              style: TextStyle(color: AppColors.textPrimary)),
          iconTheme: const IconThemeData(color: AppColors.textPrimary),
          bottom: const TabBar(
            labelColor: AppColors.cyan,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.cyan,
            tabs: [
              Tab(text: 'Active'),
              Tab(text: 'Templates'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _ActiveTab(),
            _TemplatesTab(),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Active Tab
// ---------------------------------------------------------------------------

class _ActiveTab extends ConsumerWidget {
  const _ActiveTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final taskState = ref.watch(taskProvider);
    final openInstances = taskState.openInstances;

    if (openInstances.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.task_alt_rounded,
                  size: 60, color: AppColors.inactive),
              SizedBox(height: 16),
              Text(
                'No active tasks',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Start one from the Templates tab',
                textAlign: TextAlign.center,
                style:
                    TextStyle(color: AppColors.textSecondary, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    final templates = taskState.templates;

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: openInstances.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final instance = openInstances[index];
        final template = templates.cast<TaskTemplate?>().firstWhere(
              (t) => t?.id == instance.templateId,
              orElse: () => null,
            );
        final title = template?.title ?? 'Task';
        return _InstanceCard(
          instance: instance,
          title: title,
          template: template,
          onTap: () => _showInstanceDetail(context, instance, title, ref),
        );
      },
    );
  }

  void _showInstanceDetail(
    BuildContext context,
    TaskInstance instance,
    String title,
    WidgetRef ref,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _InstanceDetailPage(
          instanceId: instance.id,
          title: title,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Instance Card
// ---------------------------------------------------------------------------

class _InstanceCard extends StatelessWidget {
  final TaskInstance instance;
  final String title;
  final TaskTemplate? template;
  final VoidCallback onTap;

  const _InstanceCard({
    required this.instance,
    required this.title,
    required this.template,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final progress = instance.progress;
    final doneCount = instance.checklistItems
        .where((i) => i.status == ChecklistItemStatus.done)
        .length;
    final total = instance.checklistItems.length;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _StatusBadge(status: instance.status),
              ],
            ),
            if (template != null) ...[
              const SizedBox(height: 4),
              _CategoryBadge(category: template!.category),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: AppColors.border,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.cyan),
                    borderRadius: BorderRadius.circular(4),
                    minHeight: 6,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '$doneCount / $total',
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Instance Detail Page
// ---------------------------------------------------------------------------

class _InstanceDetailPage extends ConsumerWidget {
  final String instanceId;
  final String title;

  const _InstanceDetailPage({
    required this.instanceId,
    required this.title,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final taskState = ref.watch(taskProvider);
    final instance = taskState.instances.cast<TaskInstance?>().firstWhere(
          (i) => i?.id == instanceId,
          orElse: () => null,
        );

    if (instance == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          title: Text(title,
              style: const TextStyle(color: AppColors.textPrimary)),
          iconTheme: const IconThemeData(color: AppColors.textPrimary),
        ),
        body: const Center(
          child: Text('Task not found.',
              style: TextStyle(color: AppColors.textMuted)),
        ),
      );
    }

    final progress = instance.progress;
    final doneCount = instance.checklistItems
        .where((i) => i.status == ChecklistItemStatus.done)
        .length;
    final total = instance.checklistItems.length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text(title,
            style: const TextStyle(color: AppColors.textPrimary)),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        actions: [
          if (instance.status != TaskStatus.done)
            TextButton(
              onPressed: () async {
                await ref
                    .read(taskProvider.notifier)
                    .completeInstance(instanceId);
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Complete',
                  style: TextStyle(color: AppColors.cyan)),
            ),
        ],
      ),
      body: Column(
        children: [
          // Progress bar
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: AppColors.border,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.cyan),
                    borderRadius: BorderRadius.circular(4),
                    minHeight: 7,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '$doneCount / $total',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
          const Divider(color: AppColors.border, height: 1),
          // Checklist
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: instance.checklistItems.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: 8),
              itemBuilder: (context, idx) {
                final item = instance.checklistItems[idx];
                return _ChecklistItemRow(
                  item: item,
                  onDone: () async {
                    await ref
                        .read(taskProvider.notifier)
                        .updateChecklistItem(
                          instanceId,
                          item.id,
                          ChecklistItemStatus.done,
                        );
                  },
                  onIssue: () => _handleIssue(
                      context, ref, instanceId, item),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleIssue(
    BuildContext context,
    WidgetRef ref,
    String instanceId,
    TaskChecklistItem item,
  ) async {
    final controller = TextEditingController(text: item.title);
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        title: const Text('Create Issue',
            style: TextStyle(color: AppColors.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(
            labelText: 'Issue title',
            labelStyle: TextStyle(color: AppColors.textMuted),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.border),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.danger),
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
            child: const Text('Create',
                style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );

    if (title != null && title.isNotEmpty) {
      final ticket = await ref.read(issueProvider.notifier).create(
            title: title,
            source: IssueSource.checklist,
            severity: IssueSeverity.medium,
          );
      await ref.read(taskProvider.notifier).updateChecklistItem(
            instanceId,
            item.id,
            ChecklistItemStatus.issue,
            issueId: ticket.id,
          );
    }
  }
}

// ---------------------------------------------------------------------------
// Checklist Item Row
// ---------------------------------------------------------------------------

class _ChecklistItemRow extends StatelessWidget {
  final TaskChecklistItem item;
  final VoidCallback onDone;
  final VoidCallback onIssue;

  const _ChecklistItemRow({
    required this.item,
    required this.onDone,
    required this.onIssue,
  });

  @override
  Widget build(BuildContext context) {
    final isDone = item.status == ChecklistItemStatus.done;
    final isIssue = item.status == ChecklistItemStatus.issue;
    final isPending = item.status == ChecklistItemStatus.pending;

    Color borderColor = AppColors.border;
    if (isDone) borderColor = AppColors.success.withAlpha(80);
    if (isIssue) borderColor = AppColors.danger.withAlpha(80);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          // Status icon
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: isDone
                  ? AppColors.success.withAlpha(25)
                  : isIssue
                      ? AppColors.danger.withAlpha(25)
                      : AppColors.border.withAlpha(60),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isDone
                  ? Icons.check_rounded
                  : isIssue
                      ? Icons.warning_amber_rounded
                      : Icons.radio_button_unchecked_rounded,
              size: 16,
              color: isDone
                  ? AppColors.success
                  : isIssue
                      ? AppColors.danger
                      : AppColors.textMuted,
            ),
          ),
          const SizedBox(width: 12),
          // Title
          Expanded(
            child: Text(
              item.title,
              style: TextStyle(
                color: isDone
                    ? AppColors.textMuted
                    : AppColors.textPrimary,
                fontSize: 14,
                decoration: isDone ? TextDecoration.lineThrough : null,
                decorationColor: AppColors.textMuted,
              ),
            ),
          ),
          // Buttons
          if (isPending) ...[
            const SizedBox(width: 8),
            _MiniButton(
              label: 'Done',
              color: AppColors.success,
              onTap: onDone,
            ),
            const SizedBox(width: 6),
            _MiniButton(
              label: 'Issue',
              color: AppColors.danger,
              onTap: onIssue,
            ),
          ] else if (isIssue)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.danger.withAlpha(25),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: AppColors.danger.withAlpha(80)),
              ),
              child: const Text(
                'ISSUE',
                style: TextStyle(
                  color: AppColors.danger,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _MiniButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withAlpha(22),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: color.withAlpha(80)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Templates Tab
// ---------------------------------------------------------------------------

class _TemplatesTab extends ConsumerWidget {
  const _TemplatesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(taskProvider).templates;

    if (templates.isEmpty) {
      return const Center(
        child: Text('No templates available.',
            style: TextStyle(color: AppColors.textMuted)),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: templates.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final template = templates[index];
        return _TemplateCard(
          template: template,
          onStart: () async {
            await ref
                .read(taskProvider.notifier)
                .createInstance(template.id);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Task started'),
                  backgroundColor: AppColors.cardBg,
                  behavior: SnackBarBehavior.floating,
                  duration: Duration(seconds: 2),
                ),
              );
            }
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Template Card
// ---------------------------------------------------------------------------

class _TemplateCard extends StatelessWidget {
  final TaskTemplate template;
  final VoidCallback onStart;

  const _TemplateCard({required this.template, required this.onStart});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  template.title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (template.isBuiltIn)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.inactive.withAlpha(30),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                        color: AppColors.inactive.withAlpha(70)),
                  ),
                  child: const Text(
                    'BUILT-IN',
                    style: TextStyle(
                      color: AppColors.inactive,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _CategoryBadge(category: template.category),
              const SizedBox(width: 8),
              Text(
                '${template.checklistItems.length} items',
                style: const TextStyle(
                    color: AppColors.textMuted, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.cyan,
                foregroundColor: AppColors.background,
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9)),
              ),
              onPressed: onStart,
              child: const Text(
                'Start',
                style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Category Badge
// ---------------------------------------------------------------------------

class _CategoryBadge extends StatelessWidget {
  final TaskCategory category;
  const _CategoryBadge({required this.category});

  static const _labels = {
    TaskCategory.preDeparture: 'Pre-Departure',
    TaskCategory.postArrival: 'Post-Arrival',
    TaskCategory.safety: 'Safety',
    TaskCategory.periodic: 'Periodic',
    TaskCategory.custom: 'Custom',
  };

  static const _colors = {
    TaskCategory.preDeparture: AppColors.cyan,
    TaskCategory.postArrival: AppColors.teal,
    TaskCategory.safety: AppColors.danger,
    TaskCategory.periodic: AppColors.warning,
    TaskCategory.custom: AppColors.inactive,
  };

  @override
  Widget build(BuildContext context) {
    final label = _labels[category] ?? category.name;
    final color = _colors[category] ?? AppColors.inactive;
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
// Status Badge
// ---------------------------------------------------------------------------

class _StatusBadge extends StatelessWidget {
  final TaskStatus status;
  const _StatusBadge({required this.status});

  static const _labels = {
    TaskStatus.open: 'Open',
    TaskStatus.inProgress: 'In Progress',
    TaskStatus.done: 'Done',
    TaskStatus.skipped: 'Skipped',
  };

  static const _colors = {
    TaskStatus.open: AppColors.inactive,
    TaskStatus.inProgress: AppColors.cyan,
    TaskStatus.done: AppColors.success,
    TaskStatus.skipped: AppColors.textMuted,
  };

  @override
  Widget build(BuildContext context) {
    final label = _labels[status] ?? status.name;
    final color = _colors[status] ?? AppColors.inactive;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
