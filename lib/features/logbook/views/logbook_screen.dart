import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/models/logbook_entry.dart';
import '../../../core/providers/vessel_provider.dart';

final _logbookProvider = Provider<Box>((ref) => Hive.box('logbook'));

class LogbookScreen extends ConsumerStatefulWidget {
  const LogbookScreen({super.key});

  @override
  ConsumerState<LogbookScreen> createState() => _LogbookScreenState();
}

class _LogbookScreenState extends ConsumerState<LogbookScreen> {
  List<LogbookEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  void _loadEntries() {
    final box = ref.read(_logbookProvider);
    final entries = box.values
        .map((v) => LogbookEntry.fromMap(v as Map))
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    setState(() => _entries = entries);
  }

  Future<void> _addEntry(LogbookEntryType type, {String notes = ''}) async {
    final vessel = ref.read(vesselProvider);
    final entry = LogbookEntry.fromVesselState(vessel, type: type, notes: notes);
    final box = ref.read(_logbookProvider);
    await box.put(entry.id, entry.toMap());
    _loadEntries();
  }

  Future<void> _deleteEntry(String id) async {
    final box = ref.read(_logbookProvider);
    await box.delete(id);
    _loadEntries();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Logbook'),
        actions: [
          PopupMenuButton<LogbookEntryType>(
            icon: const Icon(Icons.add_rounded),
            color: AppColors.cardBg,
            onSelected: (type) async {
              if (type == LogbookEntryType.manual) {
                await _showManualEntryDialog();
              } else {
                await _addEntry(type);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                  value: LogbookEntryType.departure,
                  child: Text('Departure')),
              const PopupMenuItem(
                  value: LogbookEntryType.arrival,
                  child: Text('Arrival')),
              const PopupMenuItem(
                  value: LogbookEntryType.waypoint,
                  child: Text('Waypoint')),
              const PopupMenuItem(
                  value: LogbookEntryType.weather,
                  child: Text('Weather note')),
              const PopupMenuItem(
                  value: LogbookEntryType.manual,
                  child: Text('Manual entry…')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: _entries.isEmpty
            ? _EmptyLogbook()
            : ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: _entries.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final entry = _entries[index];
                  return _LogEntry(
                    entry: entry,
                    onDelete: () => _deleteEntry(entry.id),
                  );
                },
              ),
      ),
    );
  }

  Future<void> _showManualEntryDialog() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.dialogBg,
        title: const Text('Manual Entry'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Enter log notes…'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      await _addEntry(LogbookEntryType.manual, notes: result);
    }
  }
}

class _EmptyLogbook extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_stories_rounded, size: 64, color: AppColors.inactive),
            SizedBox(height: 16),
            Text('No entries yet',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
            SizedBox(height: 8),
            Text('Tap + to add your first log entry.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
          ],
        ),
      );
}

class _LogEntry extends StatelessWidget {
  final LogbookEntry entry;
  final VoidCallback onDelete;

  const _LogEntry({required this.entry, required this.onDelete});

  static const _typeColors = <LogbookEntryType, Color>{
    LogbookEntryType.departure: AppColors.success,
    LogbookEntryType.arrival: AppColors.cyan,
    LogbookEntryType.waypoint: AppColors.teal,
    LogbookEntryType.mob: AppColors.danger,
    LogbookEntryType.weather: AppColors.modWeather,
    LogbookEntryType.manual: AppColors.modLogbook,
    LogbookEntryType.auto: AppColors.inactive,
  };

  static const _typeIcons = <LogbookEntryType, IconData>{
    LogbookEntryType.departure: Icons.sailing_rounded,
    LogbookEntryType.arrival: Icons.anchor_rounded,
    LogbookEntryType.waypoint: Icons.flag_rounded,
    LogbookEntryType.mob: Icons.person_off_rounded,
    LogbookEntryType.weather: Icons.cloud_rounded,
    LogbookEntryType.manual: Icons.edit_rounded,
    LogbookEntryType.auto: Icons.timer_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final color = _typeColors[entry.type] ?? AppColors.textSecondary;
    final icon = _typeIcons[entry.type] ?? Icons.note_rounded;
    final dateStr = DateFormat('d MMM HH:mm').format(entry.timestamp);

    return Dismissible(
      key: Key(entry.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: AppColors.danger.withAlpha(40),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_rounded, color: AppColors.danger),
      ),
      onDismissed: (_) => onDelete(),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Type icon
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withAlpha(28),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        entry.type.name.toUpperCase(),
                        style: TextStyle(
                          color: color,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const Spacer(),
                      Text(dateStr,
                          style: const TextStyle(
                              color: AppColors.textMuted, fontSize: 11)),
                    ],
                  ),
                  if (entry.notes.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(entry.notes,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 13)),
                  ],
                  if (entry.position != null) ...[
                    const SizedBox(height: 4),
                    Row(children: [
                      const Icon(Icons.location_on_rounded,
                          size: 11, color: AppColors.textMuted),
                      const SizedBox(width: 3),
                      Text(
                        '${entry.position!.latitude.toStringAsFixed(4)}°, '
                        '${entry.position!.longitude.toStringAsFixed(4)}°',
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (entry.speedOverGround != null) ...[
                        const SizedBox(width: 10),
                        const Icon(Icons.speed_rounded,
                            size: 11, color: AppColors.textMuted),
                        const SizedBox(width: 3),
                        Text(
                          '${entry.speedOverGround!.toStringAsFixed(1)} kn',
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ]),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
