import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/providers/log_provider.dart';
import '../../../core/models/log_entry.dart';

// ---------------------------------------------------------------------------
// Filter enum mirrors LogEntryType plus an "All" sentinel
// ---------------------------------------------------------------------------

enum _LogFilter {
  all,
  navigation,
  power,
  ais,
  manual,
  system,
  alarm,
}

extension _LogFilterExt on _LogFilter {
  String get label {
    switch (this) {
      case _LogFilter.all:
        return 'All';
      case _LogFilter.navigation:
        return 'Navigation';
      case _LogFilter.power:
        return 'Power';
      case _LogFilter.ais:
        return 'AIS';
      case _LogFilter.manual:
        return 'Manual';
      case _LogFilter.system:
        return 'System';
      case _LogFilter.alarm:
        return 'Alarm';
    }
  }

  LogEntryType? get type {
    switch (this) {
      case _LogFilter.all:
        return null;
      case _LogFilter.navigation:
        return LogEntryType.navigation;
      case _LogFilter.power:
        return LogEntryType.power;
      case _LogFilter.ais:
        return LogEntryType.ais;
      case _LogFilter.manual:
        return LogEntryType.manual;
      case _LogFilter.system:
        return LogEntryType.system;
      case _LogFilter.alarm:
        return LogEntryType.alarm;
    }
  }
}

// ---------------------------------------------------------------------------
// LogScreen
// ---------------------------------------------------------------------------

class LogScreen extends ConsumerStatefulWidget {
  const LogScreen({super.key});

  @override
  ConsumerState<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends ConsumerState<LogScreen> {
  _LogFilter _activeFilter = _LogFilter.all;

  void _showManualLogDialog() {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        title: const Text('Add Log Entry',
            style: TextStyle(color: AppColors.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(
            hintText: 'Enter message…',
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
                      message: text,
                    );
              }
            },
            child:
                const Text('Add', style: TextStyle(color: AppColors.cyan)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allEntries = ref.watch(logProvider);

    // Filter + sort by timestamp desc
    final filtered = allEntries
        .where((e) =>
            _activeFilter == _LogFilter.all ||
            e.type == _activeFilter.type)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('Log',
            style: TextStyle(color: AppColors.textPrimary)),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list_rounded,
                color: AppColors.textSecondary),
            tooltip: 'Filter',
            onPressed: () {
              // Filter is always visible via chips — icon is decorative
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.teal,
        foregroundColor: AppColors.background,
        onPressed: _showManualLogDialog,
        child: const Icon(Icons.edit_rounded),
      ),
      body: Column(
        children: [
          // ---- Filter chips ----
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              children: _LogFilter.values.map((filter) {
                final isActive = _activeFilter == filter;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () =>
                        setState(() => _activeFilter = filter),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: isActive
                            ? AppColors.cyan.withAlpha(35)
                            : AppColors.cardBg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isActive
                              ? AppColors.cyan.withAlpha(180)
                              : AppColors.border,
                          width: isActive ? 1.5 : 1,
                        ),
                      ),
                      child: Text(
                        filter.label,
                        style: TextStyle(
                          color: isActive
                              ? AppColors.cyan
                              : AppColors.textSecondary,
                          fontSize: 13,
                          fontWeight: isActive
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const Divider(color: AppColors.border, height: 1),

          // ---- Log entries ----
          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.subject_rounded,
                              size: 56, color: AppColors.inactive),
                          SizedBox(height: 14),
                          Text(
                            'No log entries yet',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Events and manual entries will appear here.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      return _LogEntryRow(entry: filtered[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Log Entry Row
// ---------------------------------------------------------------------------

class _LogEntryRow extends StatelessWidget {
  final LogEntry entry;
  const _LogEntryRow({required this.entry});

  static const _typeConfig = <LogEntryType, ({IconData icon, Color color})>{
    LogEntryType.system: (
      icon: Icons.settings_rounded,
      color: AppColors.inactive,
    ),
    LogEntryType.alarm: (
      icon: Icons.warning_rounded,
      color: AppColors.danger,
    ),
    LogEntryType.navigation: (
      icon: Icons.navigation_rounded,
      color: AppColors.cyan,
    ),
    LogEntryType.power: (
      icon: Icons.bolt_rounded,
      color: AppColors.warning,
    ),
    LogEntryType.ais: (
      icon: Icons.directions_boat_rounded,
      color: Color(0xFF0A84FF),
    ),
    LogEntryType.manual: (
      icon: Icons.edit_note_rounded,
      color: AppColors.teal,
    ),
    LogEntryType.maintenance: (
      icon: Icons.build_rounded,
      color: Color(0xFFFF9F0A),
    ),
  };

  static Color _bgColor(LogEntryType type) {
    switch (type) {
      case LogEntryType.alarm:
        return AppColors.danger.withAlpha(10);
      case LogEntryType.navigation:
        return AppColors.cyan.withAlpha(8);
      case LogEntryType.power:
        return AppColors.warning.withAlpha(8);
      case LogEntryType.ais:
        return const Color(0xFF0A84FF).withAlpha(8);
      case LogEntryType.manual:
        return AppColors.teal.withAlpha(8);
      default:
        return AppColors.cardBg;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = _typeConfig[entry.type] ??
        (icon: Icons.info_outline_rounded, color: AppColors.textMuted);
    final timeFmt =
        DateFormat('HH:mm dd/MM').format(entry.timestamp.toLocal());

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _bgColor(entry.type),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Icon
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: cfg.color.withAlpha(25),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(cfg.icon, size: 17, color: cfg.color),
          ),
          const SizedBox(width: 12),
          // Message + subtype
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  entry.message,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (entry.subtype != null && entry.subtype!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    entry.subtype!,
                    style: TextStyle(
                      color: cfg.color,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Timestamp
          Text(
            timeFmt,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
