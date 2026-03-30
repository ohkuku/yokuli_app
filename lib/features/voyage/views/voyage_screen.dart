import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/providers/voyage_provider.dart';
import '../../../core/providers/log_provider.dart';
import '../../../core/models/voyage.dart';
import '../../../core/models/log_entry.dart';

class VoyageScreen extends ConsumerStatefulWidget {
  const VoyageScreen({super.key});

  @override
  ConsumerState<VoyageScreen> createState() => _VoyageScreenState();
}

class _VoyageScreenState extends ConsumerState<VoyageScreen> {
  Timer? _durationTimer;

  @override
  void initState() {
    super.initState();
    // Tick every second to update live elapsed time display
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _startVoyage() async {
    await ref
        .read(voyageProvider.notifier)
        .startVoyage(VoyageSource.manual, position: null);
  }

  Future<void> _confirmEndVoyage() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        title: const Text('End Voyage',
            style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'Are you sure you want to end the current voyage?',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('End Voyage',
                style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(voyageProvider.notifier).endVoyage();
    }
  }

  Future<void> _addManualNote() async {
    final voyageState = ref.read(voyageProvider);
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        title: const Text('Add Note',
            style: TextStyle(color: AppColors.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary),
          maxLines: 3,
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
            onPressed: () {
              final text = controller.text.trim();
              Navigator.pop(ctx);
              if (text.isNotEmpty) {
                ref.read(logProvider.notifier).log(
                      type: LogEntryType.manual,
                      subtype: '备注',
                      message: text,
                      voyageId: voyageState.active?.id,
                    );
              }
            },
            child: const Text('Add',
                style: TextStyle(color: AppColors.cyan)),
          ),
        ],
      ),
    );
  }

  void _quickLog(String label) {
    final voyageState = ref.read(voyageProvider);
    ref.read(logProvider.notifier).log(
          type: LogEntryType.navigation,
          subtype: label,
          message: 'Quick log: $label',
          voyageId: voyageState.active?.id,
        );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Logged: $label'),
        backgroundColor: AppColors.cardBg,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final voyageState = ref.watch(voyageProvider);
    final active = voyageState.active;
    final history = [...voyageState.history]
      ..sort((a, b) => b.startTime.compareTo(a.startTime));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('Voyage',
            style: TextStyle(color: AppColors.textPrimary)),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ---- Active voyage card ----
            if (active != null) ...[
              _ActiveVoyageCard(
                voyage: active,
                onEndVoyage: _confirmEndVoyage,
                onAddNote: _addManualNote,
              ),
              const SizedBox(height: 16),
            ],

            // ---- Quick log buttons ----
            _QuickLogSection(onLog: _quickLog),
            const SizedBox(height: 16),

            // ---- Start voyage (only when no active voyage) ----
            if (active == null) ...[
              _StartVoyageCard(onStart: _startVoyage),
              const SizedBox(height: 16),
            ],

            // ---- History section ----
            const _SectionLabel('HISTORY'),
            const SizedBox(height: 8),
            if (history.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'No voyage history yet.',
                    style:
                        TextStyle(color: AppColors.textMuted, fontSize: 14),
                  ),
                ),
              )
            else
              ...history.map(
                (s) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _VoyageHistoryTile(voyage: s),
                ),
              ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Active Voyage Card
// ---------------------------------------------------------------------------

class _ActiveVoyageCard extends StatelessWidget {
  final VoyageSession voyage;
  final VoidCallback onEndVoyage;
  final VoidCallback onAddNote;

  const _ActiveVoyageCard({
    required this.voyage,
    required this.onEndVoyage,
    required this.onAddNote,
  });

  @override
  Widget build(BuildContext context) {
    final dur = voyage.duration;
    final h = dur.inHours;
    final m = (dur.inMinutes % 60).toString().padLeft(2, '0');
    final s = (dur.inSeconds % 60).toString().padLeft(2, '0');
    final elapsedStr = '$h:$m:$s';
    final startFmt =
        DateFormat('HH:mm dd/MMM').format(voyage.startTime.toLocal());

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.success.withAlpha(80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'ACTIVE VOYAGE',
                  style: TextStyle(
                    color: AppColors.success,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                  ),
                ),
                const Spacer(),
                _SourceBadge(source: voyage.source),
              ],
            ),
          ),
          const Divider(color: AppColors.border, height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Start time
                Row(
                  children: [
                    const Icon(Icons.schedule_rounded,
                        size: 14, color: AppColors.textMuted),
                    const SizedBox(width: 6),
                    Text(
                      'Started $startFmt',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Elapsed timer
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    const Icon(Icons.timer_outlined,
                        size: 16, color: AppColors.cyan),
                    const SizedBox(width: 8),
                    Text(
                      elapsedStr,
                      style: const TextStyle(
                        color: AppColors.cyan,
                        fontSize: 30,
                        fontWeight: FontWeight.w300,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'elapsed',
                      style: TextStyle(
                          color: AppColors.textMuted, fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.danger,
                          side: const BorderSide(color: AppColors.danger),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.stop_circle_outlined,
                            size: 18),
                        label: const Text('End Voyage'),
                        onPressed: onEndVoyage,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.teal,
                          side: const BorderSide(color: AppColors.teal),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.edit_note_rounded, size: 18),
                        label: const Text('Add Note'),
                        onPressed: onAddNote,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quick Log Section
// ---------------------------------------------------------------------------

class _QuickLogSection extends StatelessWidget {
  final void Function(String label) onLog;
  const _QuickLogSection({required this.onLog});

  static const _buttons = [
    ('起航', Icons.sailing_rounded, AppColors.cyan),
    ('到港', Icons.anchor_rounded, AppColors.teal),
    ('抛锚', Icons.anchor_rounded, AppColors.warning),
    ('起锚', Icons.upgrade_rounded, AppColors.success),
    ('备注', Icons.edit_note_rounded, AppColors.inactive),
    ('异常', Icons.warning_amber_rounded, AppColors.danger),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'QUICK LOG',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _buttons.map((entry) {
              final (label, icon, color) = entry;
              return GestureDetector(
                onTap: () => onLog(label),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: color.withAlpha(20),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: color.withAlpha(70)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 15, color: color),
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: TextStyle(
                          color: color,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Start Voyage Card
// ---------------------------------------------------------------------------

class _StartVoyageCard extends StatelessWidget {
  final VoidCallback onStart;
  const _StartVoyageCard({required this.onStart});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.sailing_rounded, size: 44, color: AppColors.cyan),
          const SizedBox(height: 12),
          const Text(
            'No active voyage',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Start a voyage to track your trip and log events.',
            textAlign: TextAlign.center,
            style:
                TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.cyan,
              foregroundColor: AppColors.background,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.play_arrow_rounded, size: 20),
            label: const Text(
              'Start Voyage',
              style:
                  TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            onPressed: onStart,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Voyage History Tile
// ---------------------------------------------------------------------------

class _VoyageHistoryTile extends StatelessWidget {
  final VoyageSession voyage;
  const _VoyageHistoryTile({required this.voyage});

  @override
  Widget build(BuildContext context) {
    final isActive = voyage.isActive;
    final dotColor = isActive ? AppColors.success : AppColors.inactive;

    final startStr =
        DateFormat('dd MMM yyyy HH:mm').format(voyage.startTime.toLocal());

    String durationStr;
    if (isActive) {
      durationStr = 'active';
    } else {
      final dur = voyage.endTime!.difference(voyage.startTime);
      final h = dur.inHours;
      final m = dur.inMinutes % 60;
      durationStr = h > 0 ? '${h}h ${m}m' : '${m}m';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(top: 2),
            decoration:
                BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  startStr,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  durationStr,
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          _SourceBadge(source: voyage.source),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Source Badge
// ---------------------------------------------------------------------------

class _SourceBadge extends StatelessWidget {
  final VoyageSource source;
  const _SourceBadge({required this.source});

  @override
  Widget build(BuildContext context) {
    final isAuto = source == VoyageSource.auto;
    final label = isAuto ? 'AUTO' : 'MANUAL';
    final color = isAuto ? AppColors.teal : AppColors.inactive;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section Label
// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
        ),
      );
}
