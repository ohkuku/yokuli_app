import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/models/maintenance_record.dart';

final _maintenanceProvider = Provider<Box>((ref) => Hive.box('maintenance'));

class MaintenanceScreen extends ConsumerStatefulWidget {
  const MaintenanceScreen({super.key});

  @override
  ConsumerState<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends ConsumerState<MaintenanceScreen> {
  List<MaintenanceRecord> _records = [];

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  void _loadRecords() {
    final box = ref.read(_maintenanceProvider);
    final records = box.values
        .map((v) => MaintenanceRecord.fromMap(v as Map))
        .toList()
      ..sort((a, b) => a.status.index.compareTo(b.status.index));
    setState(() => _records = records);
  }

  Future<void> _saveRecord(MaintenanceRecord record) async {
    final box = ref.read(_maintenanceProvider);
    await box.put(record.id, record.toMap());
    _loadRecords();
  }

  Future<void> _deleteRecord(String id) async {
    final box = ref.read(_maintenanceProvider);
    await box.delete(id);
    _loadRecords();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Maintenance')),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        child: const Icon(Icons.add_rounded),
      ),
      body: SafeArea(
        child: _records.isEmpty
            ? _EmptyMaintenance(onAdd: _showAddDialog)
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
                itemCount: _records.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final record = _records[index];
                  return _MaintenanceCard(
                    record: record,
                    onMarkDone: () => _saveRecord(record.copyWith(
                      lastDoneDate: DateTime.now(),
                      status: MaintenanceStatus.completed,
                    )),
                    onDelete: () => _deleteRecord(record.id),
                    onEdit: () => _showEditDialog(record),
                  );
                },
              ),
      ),
    );
  }

  Future<void> _showAddDialog() => _showRecordDialog(null);
  Future<void> _showEditDialog(MaintenanceRecord record) =>
      _showRecordDialog(record);

  Future<void> _showRecordDialog(MaintenanceRecord? existing) async {
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    String category = existing?.systemCategory ?? 'General';
    RecurrenceType recType = existing?.recurrenceType ?? RecurrenceType.none;
    double recValue = (existing?.recurrenceValue ?? 90).toDouble();

    final categories = ['General', 'Engine', 'Electrical', 'Hull', 'Safety', 'Rigging', 'Navigation'];

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => Padding(
          padding: EdgeInsets.fromLTRB(
              16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(existing == null ? 'Add Task' : 'Edit Task',
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 16),
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'Task title'),
                  autofocus: true,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(labelText: 'Description (optional)'),
                  maxLines: 2,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: category,
                  dropdownColor: AppColors.dialogBg,
                  decoration: const InputDecoration(labelText: 'System'),
                  items: categories
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) => setSt(() => category = v!),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<RecurrenceType>(
                  value: recType,
                  dropdownColor: AppColors.dialogBg,
                  decoration: const InputDecoration(labelText: 'Recurrence'),
                  items: const [
                    DropdownMenuItem(value: RecurrenceType.none, child: Text('No recurrence')),
                    DropdownMenuItem(value: RecurrenceType.days, child: Text('Every N days')),
                    DropdownMenuItem(value: RecurrenceType.months, child: Text('Every N months')),
                  ],
                  onChanged: (v) => setSt(() => recType = v!),
                ),
                if (recType != RecurrenceType.none) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: recValue,
                          min: 1,
                          max: recType == RecurrenceType.days ? 365 : 24,
                          divisions: recType == RecurrenceType.days ? 36 : 24,
                          activeColor: AppColors.cyan,
                          inactiveColor: AppColors.gaugeTrack,
                          onChanged: (v) => setSt(() => recValue = v),
                        ),
                      ),
                      Text(
                        recType == RecurrenceType.days
                            ? '${recValue.round()} days'
                            : '${recValue.round()} months',
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () async {
                        if (titleCtrl.text.trim().isEmpty) return;
                        final record = (existing ?? MaintenanceRecord(
                          id: DateTime.now().millisecondsSinceEpoch.toString(),
                          title: '',
                        )).copyWith(
                          title: titleCtrl.text.trim(),
                          description: descCtrl.text.trim(),
                          systemCategory: category,
                          recurrenceType: recType,
                          recurrenceValue: recType == RecurrenceType.none
                              ? null
                              : recValue.round(),
                        );
                        Navigator.pop(ctx);
                        await _saveRecord(record);
                      },
                      child: Text(existing == null ? 'Add' : 'Save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyMaintenance extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyMaintenance({required this.onAdd});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.build_rounded, size: 64, color: AppColors.inactive),
            const SizedBox(height: 16),
            const Text('No maintenance tasks',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
            const SizedBox(height: 8),
            const Text('Track recurring maintenance for your vessel.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add first task'),
            ),
          ],
        ),
      );
}

class _MaintenanceCard extends StatelessWidget {
  final MaintenanceRecord record;
  final VoidCallback onMarkDone;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const _MaintenanceCard({
    required this.record,
    required this.onMarkDone,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final isOverdue = record.nextDueDate != null &&
        record.nextDueDate!.isBefore(DateTime.now());
    final color = isOverdue
        ? AppColors.danger
        : record.status == MaintenanceStatus.completed
            ? AppColors.success
            : AppColors.modMaintenance;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOverdue ? AppColors.danger.withAlpha(80) : AppColors.border,
        ),
      ),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status circle
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withAlpha(28),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  record.status == MaintenanceStatus.completed
                      ? Icons.check_rounded
                      : isOverdue
                          ? Icons.warning_rounded
                          : Icons.build_rounded,
                  color: color,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(record.title,
                              style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(record.systemCategory,
                              style: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                    if (record.description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(record.description,
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 12)),
                    ],
                    const SizedBox(height: 6),
                    Row(children: [
                      if (record.lastDoneDate != null) ...[
                        const Icon(Icons.check_circle_outline_rounded,
                            size: 12, color: AppColors.textMuted),
                        const SizedBox(width: 3),
                        Text(
                          'Done: ${DateFormat('d MMM yyyy').format(record.lastDoneDate!)}',
                          style: const TextStyle(
                              color: AppColors.textMuted, fontSize: 11),
                        ),
                      ],
                      if (record.nextDueDate != null) ...[
                        const SizedBox(width: 10),
                        Icon(Icons.schedule_rounded,
                            size: 12,
                            color: isOverdue ? AppColors.danger : AppColors.textMuted),
                        const SizedBox(width: 3),
                        Text(
                          'Due: ${DateFormat('d MMM yyyy').format(record.nextDueDate!)}',
                          style: TextStyle(
                            color: isOverdue ? AppColors.danger : AppColors.textMuted,
                            fontSize: 11,
                            fontWeight:
                                isOverdue ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ],
                    ]),
                  ],
                ),
              ),

              // Action buttons
              Column(children: [
                IconButton(
                  icon: const Icon(Icons.check_rounded, color: AppColors.success, size: 20),
                  onPressed: onMarkDone,
                  tooltip: 'Mark done',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: AppColors.danger, size: 20),
                  onPressed: onDelete,
                  tooltip: 'Delete',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
