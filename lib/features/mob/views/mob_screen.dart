import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/mob_alert.dart';
import '../../../core/models/mob_trigger_rule.dart';
import '../../../core/models/vessel_state.dart';
import '../../../core/providers/vessel_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/id_gen.dart';
import '../providers/mob_provider.dart';
import '../../../app.dart' show isOnMobScreenProvider;

class MobScreen extends ConsumerStatefulWidget {
  const MobScreen({super.key});

  @override
  ConsumerState<MobScreen> createState() => _MobScreenState();
}

class _MobScreenState extends ConsumerState<MobScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    // Tell the overlay layer we're on this screen — suppresses the MOB strip.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(isOnMobScreenProvider.notifier).state = true;
    });
  }

  @override
  void dispose() {
    ref.read(isOnMobScreenProvider.notifier).state = false;
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mob = ref.watch(mobProvider);
    final isActive = mob.isMobActive;

    return PopScope(
      canPop: !isActive,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && isActive) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('MOB 告警激活中，请先解除告警')),
          );
        }
      },
      child: Scaffold(
        backgroundColor: isActive ? const Color(0xFF1a0000) : const Color(0xFF0a0f1e),
        appBar: AppBar(
          backgroundColor: isActive ? const Color(0xFF3d0000) : null,
          title: Row(
            children: [
              if (isActive)
                Container(
                  width: 10, height: 10,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: const BoxDecoration(
                    color: AppColors.danger,
                    shape: BoxShape.circle,
                  ),
                ),
              Text(
                isActive ? '⚠ MAN OVERBOARD' : 'MOB 系统',
                style: TextStyle(
                  color: isActive ? AppColors.danger : Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          bottom: TabBar(
            controller: _tabs,
            indicatorColor: isActive ? AppColors.danger : AppColors.cyan,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            tabs: const [
              Tab(text: '告警'),
              Tab(text: '规则'),
              Tab(text: '历史'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabs,
          children: [
            _ActiveTab(isActive: isActive),
            _RulesTab(),
            _HistoryTab(),
          ],
        ),
      ),
    );
  }
}

// ─── Active / Standby Tab ────────────────────────────────────────────────────

class _ActiveTab extends ConsumerStatefulWidget {
  final bool isActive;
  const _ActiveTab({required this.isActive});

  @override
  ConsumerState<_ActiveTab> createState() => _ActiveTabState();
}

class _ActiveTabState extends ConsumerState<_ActiveTab> {
  Timer? _timer;
  int _elapsedSeconds = 0;

  @override
  void initState() {
    super.initState();
    _maybeStartTimer();
  }

  @override
  void didUpdateWidget(_ActiveTab old) {
    super.didUpdateWidget(old);
    final isActive = ref.read(mobProvider).isMobActive;
    if (isActive && !old.isActive) _maybeStartTimer();
    if (!isActive && old.isActive) _stopTimer();
  }

  void _maybeStartTimer() {
    if (!ref.read(mobProvider).isMobActive) return;
    final mob = ref.read(mobProvider).activeMob;
    if (mob == null) return;
    _elapsedSeconds = mob.elapsed.inSeconds;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds++);
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    setState(() => _elapsedSeconds = 0);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isActive = ref.watch(mobProvider).isMobActive;
    return isActive ? _buildActive(context) : _buildStandby(context);
  }

  Widget _buildActive(BuildContext context) {
    final mob = ref.watch(mobProvider).activeMob;
    if (mob == null) return _buildStandby(context);
    final vessel = ref.watch(vesselProvider);

    final mins = _elapsedSeconds ~/ 60;
    final secs = _elapsedSeconds % 60;

    final mobPos = mob.position;
    final vesselPos = vessel.position;
    final dist = (mobPos != null && vesselPos != null)
        ? _distanceNm(vesselPos, mobPos)
        : null;
    final bearing = (mobPos != null && vesselPos != null)
        ? _bearing(vesselPos, mobPos)
        : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Big elapsed timer
          Container(
            padding: const EdgeInsets.symmetric(vertical: 28),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
            ),
            child: Column(
              children: [
                const Text('经过时间', style: TextStyle(color: Colors.white54, fontSize: 13)),
                const SizedBox(height: 6),
                Text(
                  '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                    color: AppColors.danger,
                    fontSize: 64,
                    fontWeight: FontWeight.w200,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  mob.triggeredAt.toLocal().toString().substring(0, 19),
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Trigger source
          _InfoCard(
            icon: Icons.info_outline,
            label: '触发来源',
            value: mob.triggerSource == 'manual'
                ? '手动触发'
                : '自动规则: ${mob.triggerRuleName ?? '未知'}',
          ),
          const SizedBox(height: 10),

          // MOB position
          if (mobPos != null)
            _InfoCard(
              icon: Icons.location_on,
              label: 'MOB 位置',
              value: '${mobPos.latitude.toStringAsFixed(5)}°N  '
                  '${mobPos.longitude.toStringAsFixed(5)}°E',
            ),
          if (mobPos != null) const SizedBox(height: 10),

          // Distance and bearing
          if (dist != null && bearing != null)
            Row(
              children: [
                Expanded(
                  child: _InfoCard(
                    icon: Icons.straighten,
                    label: '距离',
                    value: '${dist.toStringAsFixed(2)} nm',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _InfoCard(
                    icon: Icons.navigation,
                    label: '方位',
                    value: '${bearing.toStringAsFixed(0)}°',
                  ),
                ),
              ],
            ),

          const SizedBox(height: 32),

          // Recover button
          SizedBox(
            height: 56,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1a4a1a),
                foregroundColor: Colors.greenAccent,
                side: const BorderSide(color: Colors.greenAccent),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('人员已找回', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              onPressed: () => _confirmRecover(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStandby(BuildContext context) {
    final rules = ref.watch(mobProvider).rules;
    final activeRules = rules.where((r) => r.enabled).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Status
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.shield_outlined, color: Colors.green, size: 28),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('系统就绪', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 15)),
                      Text(
                        activeRules > 0
                            ? '$activeRules 条自动规则已启用'
                            : '仅手动触发（未配置规则）',
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // Hold-to-trigger button
          _HoldTriggerButton(
            onTrigger: () => ref.read(mobProvider.notifier).trigger(),
          ),

          const SizedBox(height: 32),
          const Divider(color: Colors.white12),
          const SizedBox(height: 16),
          const Text(
            '长按上方按钮 1.5 秒手动触发 MOB 告警。\n'
            '也可在"规则"页配置 SignalK 通知或 NMEA 0183 指令自动触发。',
            style: TextStyle(color: Colors.white38, fontSize: 13, height: 1.6),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRecover(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1c1c2e),
        title: const Text('确认解除', style: TextStyle(color: Colors.white)),
        content: const Text('确认人员已找回并解除 MOB 告警？', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认找回'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      ref.read(mobProvider.notifier).cancel();
    }
  }

  static double _distanceNm(GpsPosition a, GpsPosition b) {
    const r = 3440.065; // Earth radius in nautical miles
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLon = (b.longitude - a.longitude) * math.pi / 180;
    final ha = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) * math.cos(lat2) * math.sin(dLon / 2) * math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(ha), math.sqrt(1 - ha));
  }

  static double _bearing(GpsPosition from, GpsPosition to) {
    final lat1 = from.latitude * math.pi / 180;
    final lat2 = to.latitude * math.pi / 180;
    final dLon = (to.longitude - from.longitude) * math.pi / 180;
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }
}

// ─── Hold-to-trigger button ──────────────────────────────────────────────────

class _HoldTriggerButton extends StatefulWidget {
  final VoidCallback onTrigger;
  const _HoldTriggerButton({required this.onTrigger});

  @override
  State<_HoldTriggerButton> createState() => _HoldTriggerButtonState();
}

class _HoldTriggerButtonState extends State<_HoldTriggerButton>
    with SingleTickerProviderStateMixin {
  static const _holdDuration = Duration(milliseconds: 1500);
  late final AnimationController _ctrl;
  bool _holding = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: _holdDuration);
    _ctrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        HapticFeedback.heavyImpact();
        widget.onTrigger();
        _ctrl.reset();
        setState(() => _holding = false);
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        HapticFeedback.lightImpact();
        setState(() => _holding = true);
        _ctrl.forward();
      },
      onTapUp: (_) { _ctrl.reset(); setState(() => _holding = false); },
      onTapCancel: () { _ctrl.reset(); setState(() => _holding = false); },
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          return Container(
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.danger.withValues(alpha: _holding ? 0.2 : 0.08),
              border: Border.all(
                color: AppColors.danger.withValues(alpha: 0.6 + _ctrl.value * 0.4),
                width: 2,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 110, height: 110,
                  child: CircularProgressIndicator(
                    value: _ctrl.value,
                    strokeWidth: 4,
                    color: AppColors.danger,
                    backgroundColor: AppColors.danger.withValues(alpha: 0.1),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.person_off_rounded, color: AppColors.danger, size: 32),
                    const SizedBox(height: 4),
                    Text(
                      _holding ? '${((_ctrl.value) * 1.5).toStringAsFixed(1)}s' : '长按触发',
                      style: TextStyle(
                        color: AppColors.danger,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─── Rules Tab ───────────────────────────────────────────────────────────────

class _RulesTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(mobProvider).rules;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.cyan,
        child: const Icon(Icons.add),
        onPressed: () => _showAddSheet(context, ref),
      ),
      body: rules.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.rule, color: Colors.white24, size: 48),
                  const SizedBox(height: 12),
                  const Text('暂无自动触发规则', style: TextStyle(color: Colors.white38)),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => _showAddSheet(context, ref),
                    child: const Text('添加规则'),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
              itemCount: rules.length,
              itemBuilder: (context, i) => _RuleCard(
                rule: rules[i],
                onToggle: (v) => ref.read(mobProvider.notifier).toggleRule(rules[i].id, enabled: v),
                onDelete: () => _confirmDelete(context, ref, rules[i]),
                onEdit: () => _showEditSheet(context, ref, rules[i]),
              ),
            ),
    );
  }

  void _showAddSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1c1c2e),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AddRuleSheet(
        onSave: (rule) => ref.read(mobProvider.notifier).addRule(rule),
      ),
    );
  }

  void _showEditSheet(BuildContext context, WidgetRef ref, MobTriggerRule rule) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1c1c2e),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AddRuleSheet(
        existing: rule,
        onSave: (updated) => ref.read(mobProvider.notifier).updateRule(updated),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, MobTriggerRule rule) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1c1c2e),
        title: const Text('删除规则', style: TextStyle(color: Colors.white)),
        content: Text('确认删除规则「${rule.name}」？', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true) ref.read(mobProvider.notifier).deleteRule(rule.id);
  }
}

class _RuleCard extends StatelessWidget {
  final MobTriggerRule rule;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const _RuleCard({
    required this.rule,
    required this.onToggle,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final typeIcon = switch (rule.type) {
      MobTriggerType.signalkPath => Icons.alt_route,
      MobTriggerType.signalkNotification => Icons.notifications_active_outlined,
      MobTriggerType.nmeaSentence => Icons.terminal,
    };

    final summary = _configSummary();

    return Card(
      color: const Color(0xFF151525),
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Icon(typeIcon, color: rule.enabled ? AppColors.cyan : Colors.white24, size: 26),
        title: Text(rule.name, style: TextStyle(color: rule.enabled ? Colors.white : Colors.white54)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(rule.type.label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
            if (summary.isNotEmpty)
              Text(summary, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: rule.enabled,
              onChanged: onToggle,
              activeColor: AppColors.cyan,
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white38),
              color: const Color(0xFF1c1c2e),
              onSelected: (v) {
                if (v == 'edit') onEdit();
                if (v == 'delete') onDelete();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('编辑', style: TextStyle(color: Colors.white))),
                const PopupMenuItem(value: 'delete', child: Text('删除', style: TextStyle(color: AppColors.danger))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _configSummary() {
    switch (rule.type) {
      case MobTriggerType.signalkPath:
        return rule.config['path'] as String? ?? '';
      case MobTriggerType.signalkNotification:
        final p = rule.config['pathPattern'] as String? ?? '';
        final s = (rule.config['states'] as List?)?.join(', ') ?? '';
        return 'notifications.*$p  [$s]';
      case MobTriggerType.nmeaSentence:
        final t = rule.config['talkerId'] as String? ?? '';
        final st = rule.config['sentenceType'] as String? ?? '';
        final kw = rule.config['keyword'] as String? ?? '';
        return '\$${t.isEmpty ? '--' : t}$st${kw.isNotEmpty ? ' keyword:$kw' : ''}';
    }
  }
}

// ─── Add / Edit Rule Sheet ───────────────────────────────────────────────────

class _AddRuleSheet extends ConsumerStatefulWidget {
  final MobTriggerRule? existing;
  final void Function(MobTriggerRule rule) onSave;
  const _AddRuleSheet({this.existing, required this.onSave});

  @override
  ConsumerState<_AddRuleSheet> createState() => _AddRuleSheetState();
}

enum _Step { category, presets, custom }

class _AddRuleSheetState extends ConsumerState<_AddRuleSheet> {
  _Step _step = _Step.category;
  late MobTriggerType _type;
  late TextEditingController _name;
  late TextEditingController _skPath;
  late TextEditingController _skMatchState;
  late TextEditingController _notifPattern;
  final Set<String> _notifStates = {'emergency'};
  late TextEditingController _talkerId;
  late TextEditingController _sentenceType;
  late TextEditingController _keyword;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _type = e?.type ?? MobTriggerType.signalkNotification;
    _name = TextEditingController(text: e?.name ?? '');
    _skPath = TextEditingController(text: e?.config['path'] as String? ?? '');
    _skMatchState = TextEditingController(text: e?.config['matchStateEquals'] as String? ?? '');
    _notifPattern = TextEditingController(text: e?.config['pathPattern'] as String? ?? 'mob');
    if (e?.config['states'] is List) {
      _notifStates.clear();
      _notifStates.addAll((e!.config['states'] as List).map((s) => s.toString()));
    }
    _talkerId = TextEditingController(text: e?.config['talkerId'] as String? ?? '');
    _sentenceType = TextEditingController(text: e?.config['sentenceType'] as String? ?? '');
    _keyword = TextEditingController(text: e?.config['keyword'] as String? ?? '');
    if (e != null) _step = _Step.custom; // editing → go straight to form
  }

  @override
  void dispose() {
    _name.dispose(); _skPath.dispose(); _skMatchState.dispose();
    _notifPattern.dispose(); _talkerId.dispose(); _sentenceType.dispose();
    _keyword.dispose();
    super.dispose();
  }

  void _pickCategory(MobTriggerType type) =>
      setState(() { _type = type; _step = _Step.presets; });

  // Preset tapped → save immediately, no form needed
  void _pickPreset(MobTriggerRule preset) {
    final now = DateTime.now();
    widget.onSave(MobTriggerRule(
      id: generateId(),
      name: preset.name,
      enabled: true,
      type: preset.type,
      config: preset.config,
      createdAt: now,
      updatedAt: now,
    ));
    Navigator.of(context).pop();
  }

  Map<String, dynamic> _buildConfig() {
    switch (_type) {
      case MobTriggerType.signalkPath:
        return {
          'path': _skPath.text.trim(),
          if (_skMatchState.text.trim().isNotEmpty)
            'matchStateEquals': _skMatchState.text.trim(),
        };
      case MobTriggerType.signalkNotification:
        return {
          'pathPattern': _notifPattern.text.trim(),
          'states': _notifStates.toList(),
        };
      case MobTriggerType.nmeaSentence:
        return {
          'talkerId': _talkerId.text.trim().toUpperCase(),
          'sentenceType': _sentenceType.text.trim().toUpperCase(),
          if (_keyword.text.trim().isNotEmpty) 'keyword': _keyword.text.trim(),
        };
    }
  }

  void _save() {
    if (_name.text.trim().isEmpty) return;
    final now = DateTime.now();
    final e = widget.existing;
    widget.onSave(MobTriggerRule(
      id: e?.id ?? generateId(),
      name: _name.text.trim(),
      enabled: e?.enabled ?? true,
      type: _type,
      config: _buildConfig(),
      createdAt: e?.createdAt ?? now,
      updatedAt: now,
    ));
    Navigator.of(context).pop();
  }

  void _back() {
    setState(() {
      if (_step == _Step.custom && widget.existing == null) {
        _step = _Step.presets;
      } else {
        _step = _Step.category;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              children: [
                if (_step != _Step.category)
                  GestureDetector(
                    onTap: _back,
                    child: const Padding(
                      padding: EdgeInsets.only(right: 10),
                      child: Icon(Icons.arrow_back_ios, color: Colors.white54, size: 18),
                    ),
                  ),
                Text(
                  switch (_step) {
                    _Step.category => '添加触发规则',
                    _Step.presets => _type.label,
                    _Step.custom => widget.existing != null ? '编辑规则' : '自定义规则',
                  },
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (_step == _Step.category) ...[
              const Text('选择触发类型', style: TextStyle(color: Colors.white54, fontSize: 13)),
              const SizedBox(height: 12),
              _CategoryTile(
                icon: Icons.notifications_active_outlined,
                title: 'Signal K 通知',
                subtitle: '监听 notifications.* 路径的状态变化',
                onTap: () => _pickCategory(MobTriggerType.signalkNotification),
              ),
              const SizedBox(height: 8),
              _CategoryTile(
                icon: Icons.alt_route,
                title: 'Signal K 路径',
                subtitle: '监听任意 Signal K 数据路径的值变化',
                onTap: () => _pickCategory(MobTriggerType.signalkPath),
              ),
              const SizedBox(height: 8),
              _CategoryTile(
                icon: Icons.terminal,
                title: 'NMEA 0183 句子',
                subtitle: '匹配特定句子类型或关键字',
                onTap: () => _pickCategory(MobTriggerType.nmeaSentence),
              ),
            ],

            if (_step == _Step.presets) ...[
              ...(_presetsFor(_type).map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _PresetTile(
                  title: p.name,
                  subtitle: _presetSummary(p),
                  icon: switch (_type) {
                    MobTriggerType.signalkPath => Icons.alt_route,
                    MobTriggerType.signalkNotification => Icons.notifications_active_outlined,
                    MobTriggerType.nmeaSentence => Icons.terminal,
                  },
                  onTap: () => _pickPreset(p),
                ),
              ))),
              const Divider(color: Colors.white12, height: 24),
              OutlinedButton.icon(
                icon: const Icon(Icons.tune, size: 16),
                label: const Text('自定义配置'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white24),
                ),
                onPressed: () => setState(() => _step = _Step.custom),
              ),
            ],

            if (_step == _Step.custom) ...[
              _Field(label: '规则名称', controller: _name),
              const SizedBox(height: 16),
              if (_type == MobTriggerType.signalkPath) ...[
                _Field(label: 'SignalK 路径 (如: notifications.mob)', controller: _skPath),
                const SizedBox(height: 10),
                _Field(label: '仅当 state = (留空=任意值)', controller: _skMatchState),
              ],
              if (_type == MobTriggerType.signalkNotification) ...[
                _Field(label: '路径关键字 (如: mob)', controller: _notifPattern),
                const SizedBox(height: 10),
                const Text('触发状态', style: TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: ['emergency', 'alarm', 'warn', 'normal'].map((s) {
                    final selected = _notifStates.contains(s);
                    return FilterChip(
                      label: Text(s),
                      selected: selected,
                      onSelected: (v) => setState(() {
                        if (v) _notifStates.add(s); else _notifStates.remove(s);
                      }),
                      selectedColor: AppColors.danger.withValues(alpha: 0.3),
                      backgroundColor: const Color(0xFF2a2a3e),
                      labelStyle: TextStyle(color: selected ? Colors.white : Colors.white54, fontSize: 12),
                    );
                  }).toList(),
                ),
              ],
              if (_type == MobTriggerType.nmeaSentence) ...[
                Row(
                  children: [
                    Expanded(child: _Field(label: 'Talker ID (留空=任意, 如: AI)', controller: _talkerId)),
                    const SizedBox(width: 10),
                    Expanded(child: _Field(label: '句子类型 (如: MOB)', controller: _sentenceType)),
                  ],
                ),
                const SizedBox(height: 10),
                _Field(label: '关键字 (可选, 如: MOB)', controller: _keyword),
              ],
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.cyan,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _save,
                child: Text(widget.existing != null ? '保存' : '添加规则'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<MobTriggerRule> _presetsFor(MobTriggerType type) {
    final now = DateTime.now();
    return switch (type) {
      MobTriggerType.signalkNotification => [
        MobTriggerRule.presetSignalKNotification(id: '', now: now),
      ],
      MobTriggerType.signalkPath => [
        MobTriggerRule.presetSkPathManOverboard(id: '', now: now),
      ],
      MobTriggerType.nmeaSentence => [
        MobTriggerRule.presetNmeaMob(id: '', now: now),
        MobTriggerRule.presetNmeaAisSafety(id: '', now: now),
      ],
    };
  }

  String _presetSummary(MobTriggerRule p) {
    switch (p.type) {
      case MobTriggerType.signalkPath:
        return p.config['path'] as String? ?? '';
      case MobTriggerType.signalkNotification:
        final pattern = p.config['pathPattern'] as String? ?? '';
        final states = (p.config['states'] as List?)?.join(', ') ?? '';
        return 'notifications.*$pattern  [$states]';
      case MobTriggerType.nmeaSentence:
        final t = p.config['talkerId'] as String? ?? '';
        final st = p.config['sentenceType'] as String? ?? '';
        final kw = p.config['keyword'] as String? ?? '';
        return '\$${t.isEmpty ? '--' : t}$st${kw.isNotEmpty ? '  keyword:$kw' : ''}';
    }
  }
}

// ─── History Tab ─────────────────────────────────────────────────────────────

class _HistoryTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(mobProvider).history;
    if (history.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, color: Colors.white24, size: 48),
            SizedBox(height: 12),
            Text('暂无历史记录', style: TextStyle(color: Colors.white38)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: history.length,
      itemBuilder: (context, i) {
        final mob = history[i];
        final dur = mob.elapsed;
        final mins = dur.inMinutes;
        final secs = dur.inSeconds % 60;

        return Card(
          color: const Color(0xFF151525),
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: const Icon(Icons.person_off_rounded, color: AppColors.danger),
            title: Text(
              mob.triggeredAt.toLocal().toString().substring(0, 16),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '历时 ${mins}分${secs}秒  |  ${mob.triggerSource == 'manual' ? '手动' : '规则: ${mob.triggerRuleName}'}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                if (mob.position != null)
                  Text(
                    '${mob.position!.latitude.toStringAsFixed(4)}°N  ${mob.position!.longitude.toStringAsFixed(4)}°E',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoCard({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF151525),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white38, size: 18),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
              Text(value, style: const TextStyle(color: Colors.white, fontSize: 14)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  const _Field({required this.label, required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white38, fontSize: 12),
        filled: true,
        fillColor: const Color(0xFF0f0f1f),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.white12),
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _CategoryTile({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF151525),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: AppColors.cyan.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: AppColors.cyan, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 12)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white24),
            ],
          ),
        ),
      ),
    );
  }
}

class _PresetTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  const _PresetTile({required this.title, required this.subtitle, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF151525),
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        leading: Icon(icon, color: AppColors.cyan),
        title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 14)),
        subtitle: Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 12)),
        trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 14),
        onTap: onTap,
      ),
    );
  }
}
