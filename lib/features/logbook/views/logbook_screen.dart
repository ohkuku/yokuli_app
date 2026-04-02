import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/models/logbook_entry.dart';
import '../../../core/providers/vessel_provider.dart';
import '../../../core/providers/settings_provider.dart';

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

  /// For departure entries: optionally show Coastguard filing dialog first.
  Future<void> _addDepartureEntry() async {
    final settings = ref.read(settingsProvider);
    String cgNotes = '';

    if (settings.coastguardEmail.isNotEmpty &&
        settings.coastguardPassword.isNotEmpty) {
      // Show coastguard filing dialog
      final result = await showDialog<_CoastguardFilingResult>(
        context: context,
        builder: (_) => _CoastguardFilingDialog(
          vesselName: settings.vesselName,
        ),
      );
      if (result == null) return; // user dismissed dialog entirely
      cgNotes = result.cgJson ?? '';
    }

    await _addEntry(LogbookEntryType.departure, notes: cgNotes);
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
              if (type == LogbookEntryType.departure) {
                await _addDepartureEntry();
              } else if (type == LogbookEntryType.manual) {
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

// ---------------------------------------------------------------------------
// Coastguard filing result
// ---------------------------------------------------------------------------

class _CoastguardFilingResult {
  /// Serialized CG data to store in notes, or null if skipped.
  final String? cgJson;
  const _CoastguardFilingResult({this.cgJson});
}

// ---------------------------------------------------------------------------
// Coastguard filing dialog
// ---------------------------------------------------------------------------

class _CoastguardFilingDialog extends StatefulWidget {
  final String vesselName;
  const _CoastguardFilingDialog({required this.vesselName});

  @override
  State<_CoastguardFilingDialog> createState() => _CoastguardFilingDialogState();
}

class _CoastguardFilingDialogState extends State<_CoastguardFilingDialog> {
  late TextEditingController _vesselCtrl;
  late TextEditingController _fromCtrl;
  late TextEditingController _toCtrl;
  late TextEditingController _pobCtrl;
  DateTime _eta = DateTime.now().add(const Duration(hours: 4));

  @override
  void initState() {
    super.initState();
    _vesselCtrl = TextEditingController(text: widget.vesselName);
    _fromCtrl = TextEditingController();
    _toCtrl = TextEditingController();
    _pobCtrl = TextEditingController(text: '1');
  }

  @override
  void dispose() {
    _vesselCtrl.dispose();
    _fromCtrl.dispose();
    _toCtrl.dispose();
    _pobCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickEta() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _eta,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: AppColors.cyan),
        ),
        child: child!,
      ),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_eta),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: AppColors.cyan),
        ),
        child: child!,
      ),
    );
    if (time == null || !mounted) return;
    setState(() {
      _eta = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.dialogBg,
      title: Row(
        children: const [
          Icon(Icons.anchor_rounded, color: AppColors.cyan, size: 20),
          SizedBox(width: 8),
          Text('海岸警卫队出发报告',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '提交出发报告（可选）',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 14),
            _field(_vesselCtrl, '船名', Icons.directions_boat_rounded),
            const SizedBox(height: 10),
            _field(_fromCtrl, '出发地', Icons.location_on_rounded),
            const SizedBox(height: 10),
            _field(_toCtrl, '目的地', Icons.flag_rounded),
            const SizedBox(height: 10),
            _field(_pobCtrl, '船上人数', Icons.people_rounded,
                keyboardType: TextInputType.number),
            const SizedBox(height: 10),
            // ETA picker
            InkWell(
              onTap: _pickEta,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.schedule_rounded,
                        size: 16, color: AppColors.textMuted),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('预计返回时间',
                            style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                        const SizedBox(height: 2),
                        Text(
                          DateFormat('MM/dd HH:mm').format(_eta),
                          style: const TextStyle(
                              color: AppColors.textPrimary, fontSize: 13),
                        ),
                      ],
                    ),
                    const Spacer(),
                    const Icon(Icons.edit_rounded,
                        size: 14, color: AppColors.textMuted),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, const _CoastguardFilingResult()),
          child: const Text('跳过', style: TextStyle(color: AppColors.textMuted)),
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.send_rounded, size: 14),
          label: const Text('提交并记录'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.cyan,
            foregroundColor: AppColors.background,
          ),
          onPressed: () {
            final cgData = {
              'vessel': _vesselCtrl.text.trim(),
              'from': _fromCtrl.text.trim(),
              'to': _toCtrl.text.trim(),
              'eta': _eta.toIso8601String(),
              'pob': int.tryParse(_pobCtrl.text.trim()) ?? 1,
            };
            final notes = '__cg__${jsonEncode(cgData)}';
            Navigator.pop(context, _CoastguardFilingResult(cgJson: notes));
          },
        ),
      ],
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.textMuted, fontSize: 12),
        prefixIcon: Icon(icon, size: 16, color: AppColors.textMuted),
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.cyan),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty logbook
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Log entry tile
// ---------------------------------------------------------------------------

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

  bool get _hasCgData => entry.notes.contains('__cg__');

  /// Returns the display notes (strips the CG JSON prefix for display).
  String get _displayNotes {
    if (!_hasCgData) return entry.notes;
    final idx = entry.notes.indexOf('__cg__');
    final before = entry.notes.substring(0, idx).trim();
    // Try to extract CG fields for display
    try {
      final jsonStr = entry.notes.substring(idx + 6);
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final from = data['from'] as String? ?? '';
      final to = data['to'] as String? ?? '';
      final eta = data['eta'] as String?;
      final pob = data['pob'];
      final etaStr = eta != null
          ? DateFormat('MM/dd HH:mm').format(DateTime.parse(eta).toLocal())
          : '';
      final parts = [
        if (from.isNotEmpty) '从 $from',
        if (to.isNotEmpty) '→ $to',
        if (etaStr.isNotEmpty) '返回 $etaStr',
        if (pob != null) '${pob}人',
      ];
      return [if (before.isNotEmpty) before, parts.join(' · ')].join('\n');
    } catch (_) {
      return before;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _typeColors[entry.type] ?? AppColors.textSecondary;
    final icon = _typeIcons[entry.type] ?? Icons.note_rounded;
    final dateStr = DateFormat('d MMM HH:mm').format(entry.timestamp);
    final displayNotes = _displayNotes;

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
                      // CG badge
                      if (_hasCgData) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF9F0A).withOpacity(0.20),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: const Color(0xFFFF9F0A).withOpacity(0.50)),
                          ),
                          child: const Text(
                            'CG',
                            style: TextStyle(
                              color: Color(0xFFFF9F0A),
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                      const Spacer(),
                      Text(dateStr,
                          style: const TextStyle(
                              color: AppColors.textMuted, fontSize: 11)),
                    ],
                  ),
                  if (displayNotes.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(displayNotes,
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
