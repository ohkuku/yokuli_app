import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/alarm_rule.dart';
import '../../../core/providers/alarm_rule_provider.dart';
import '../../../core/providers/device_provider.dart';
import '../../../core/providers/locale_provider.dart';
import '../../../core/theme/app_colors.dart';

// ---------------------------------------------------------------------------
// Metric Chinese display names
// ---------------------------------------------------------------------------

const _metricChineseNames = {
  'sog': '航速 (SOG)',
  'depth_keel': '龙骨水深',
  'depth_surface': '水面水深',
  'battery_voltage_main': '主电池电压',
  'wind_true_speed': '真风速',
  'wind_apparent_speed': '表观风速',
  'solar_power_total': '太阳能总功率',
};

String _operatorSymbol(AlarmOperator op) {
  switch (op) {
    case AlarmOperator.greaterEqual:
      return '≥';
    case AlarmOperator.lessEqual:
      return '≤';
    case AlarmOperator.greaterThan:
      return '>';
    case AlarmOperator.lessThan:
      return '<';
  }
}

Color _levelColor(AlarmLevel level) {
  switch (level) {
    case AlarmLevel.critical:
      return AppColors.danger;
    case AlarmLevel.warning:
      return AppColors.warning;
    case AlarmLevel.info:
      return AppColors.cyan;
  }
}

// ---------------------------------------------------------------------------
// AlarmRuleEditScreen
// ---------------------------------------------------------------------------

class AlarmRuleEditScreen extends ConsumerStatefulWidget {
  final AlarmRule? existing;

  const AlarmRuleEditScreen({super.key, required this.existing});

  @override
  ConsumerState<AlarmRuleEditScreen> createState() =>
      _AlarmRuleEditScreenState();
}

class _AlarmRuleEditScreenState extends ConsumerState<AlarmRuleEditScreen> {
  // Form state
  late TextEditingController _nameCtrl;
  late AlarmLevel _level;
  late bool _enabled;

  // Condition
  late String _metric;
  late AlarmOperator _operator;
  late TextEditingController _thresholdCtrl;
  late TextEditingController _sustainCtrl; // seconds, empty = none
  late TextEditingController _cooldownCtrl; // minutes

  // Response
  late bool _respInApp;
  late bool _respSound;
  late bool _respDiscord;
  late int _snoozeMins;

  String? _nameError;
  String? _thresholdError;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _level = e?.level ?? AlarmLevel.warning;
    _enabled = e?.enabled ?? true;

    final cond = e?.condition ??
        const AlarmCondition(
          source: AlarmConditionSource.vesselMetric,
          metric: 'depth_keel',
          operator: AlarmOperator.lessEqual,
          threshold: 3.0,
          cooldownMs: 300000,
        );
    _metric = cond.metric;
    _operator = cond.operator;
    _thresholdCtrl =
        TextEditingController(text: cond.threshold.toString());
    _sustainCtrl = TextEditingController(
      text: cond.sustainMs != null
          ? (cond.sustainMs! ~/ 1000).toString()
          : '',
    );
    _cooldownCtrl = TextEditingController(
      text: (cond.cooldownMs ~/ 60000).toString(),
    );

    final resp = e?.responsePlan ??
        const AlarmResponsePlan(inApp: true, sound: true, discord: false);
    _respInApp = resp.inApp;
    _respSound = resp.sound;
    _respDiscord = resp.discord;
    _snoozeMins = e?.snoozeMins ?? 15;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _thresholdCtrl.dispose();
    _sustainCtrl.dispose();
    _cooldownCtrl.dispose();
    super.dispose();
  }

  String get _currentUnit {
    return vesselMetrics[_metric]?.$2 ?? '';
  }

  bool _validate() {
    bool valid = true;
    setState(() {
      _nameError = null;
      _thresholdError = null;
    });

    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _nameError = '请输入规则名称');
      valid = false;
    }

    final thr = double.tryParse(_thresholdCtrl.text.trim());
    if (thr == null) {
      setState(() => _thresholdError = '请输入有效数字');
      valid = false;
    }

    return valid;
  }

  void _save() {
    if (!_validate()) return;

    final device = ref.read(deviceProvider);
    final existing = widget.existing;

    final sustainMs = () {
      final s = _sustainCtrl.text.trim();
      if (s.isEmpty) return null;
      final secs = int.tryParse(s);
      return secs != null && secs > 0 ? secs * 1000 : null;
    }();

    final cooldownMs = () {
      final c = int.tryParse(_cooldownCtrl.text.trim());
      return (c != null && c > 0) ? c * 60000 : 300000;
    }();

    final condition = AlarmCondition(
      source: AlarmConditionSource.vesselMetric,
      metric: _metric,
      operator: _operator,
      threshold: double.parse(_thresholdCtrl.text.trim()),
      sustainMs: sustainMs,
      cooldownMs: cooldownMs,
    );

    final responsePlan = AlarmResponsePlan(
      inApp: _respInApp,
      sound: _respSound,
      discord: _respDiscord,
    );

    final id = existing?.id ??
        'rule_${DateTime.now().millisecondsSinceEpoch}';

    final rule = AlarmRule(
      id: id,
      name: _nameCtrl.text.trim(),
      enabled: _enabled,
      level: _level,
      condition: condition,
      responsePlan: responsePlan,
      snoozeMins: _snoozeMins,
      isBuiltIn: existing?.isBuiltIn ?? false,
      updatedAt: DateTime.now(),
      deleted: false,
      sourceDeviceId: device.deviceId,
    );

    ref.read(alarmRuleProvider.notifier).upsert(rule);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content:
              Text(_isEditing ? '规则「${rule.name}」已更新' : '规则已创建')),
    );
    Navigator.pop(context);
  }

  void _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        title: const Text(
          '删除规则',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          '确定删除「${widget.existing!.name}」？此操作不可撤销。',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              '取消',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    ref
        .read(alarmRuleProvider.notifier)
        .delete(widget.existing!.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('规则已删除')),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(stringsProvider); // locale refresh
    final isBuiltIn = widget.existing?.isBuiltIn ?? false;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        title: Text(
          _isEditing ? '编辑告警规则' : '新建告警规则',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          if (_isEditing && !isBuiltIn)
            IconButton(
              icon: const Icon(Icons.delete_rounded,
                  color: AppColors.danger),
              onPressed: _delete,
              tooltip: '删除规则',
            ),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
          children: [
            // ── Basic Info ───────────────────────────────────────────
            _SectionHeader(label: '基本信息'),
            const SizedBox(height: 10),
            _Card(
              child: Column(
                children: [
                  // Name
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(14, 4, 14, 0),
                    child: TextField(
                      controller: _nameCtrl,
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 14),
                      decoration: InputDecoration(
                        labelText: '规则名称',
                        labelStyle: const TextStyle(
                            color: AppColors.textSecondary),
                        errorText: _nameError,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(
                              color: AppColors.cyan.withAlpha(120)),
                        ),
                      ),
                    ),
                  ),
                  const Divider(height: 1, color: AppColors.divider),
                  // Enable toggle
                  SwitchListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 2),
                    title: const Text(
                      '启用规则',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14),
                    ),
                    value: _enabled,
                    activeColor: AppColors.cyan,
                    onChanged: (v) => setState(() => _enabled = v),
                  ),
                  const Divider(height: 1, color: AppColors.divider),
                  // Level selector
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(14, 10, 14, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '告警等级',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children:
                              AlarmLevel.values.map((lv) {
                            final selected = _level == lv;
                            final color = _levelColor(lv);
                            return Expanded(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(
                                        horizontal: 3),
                                child: GestureDetector(
                                  onTap: () =>
                                      setState(() => _level = lv),
                                  child: AnimatedContainer(
                                    duration: const Duration(
                                        milliseconds: 150),
                                    padding:
                                        const EdgeInsets.symmetric(
                                            vertical: 10),
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? color.withAlpha(35)
                                          : AppColors.surfaceElevated,
                                      borderRadius:
                                          BorderRadius.circular(8),
                                      border: Border.all(
                                        color: selected
                                            ? color.withAlpha(120)
                                            : AppColors.border,
                                        width: selected ? 1.5 : 0.5,
                                      ),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      lv.displayName,
                                      style: TextStyle(
                                        color: selected
                                            ? color
                                            : AppColors.textMuted,
                                        fontSize: 13,
                                        fontWeight: selected
                                            ? FontWeight.w700
                                            : FontWeight.w400,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Condition ────────────────────────────────────────────
            _SectionHeader(label: '触发条件'),
            const SizedBox(height: 10),
            _Card(
              child: Column(
                children: [
                  // Metric selector
                  _FieldRow(
                    label: '监测指标',
                    child: DropdownButton<String>(
                      value: _metric,
                      dropdownColor: AppColors.cardBg,
                      underline: const SizedBox.shrink(),
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13),
                      items: vesselMetrics.keys.map((key) {
                        final name =
                            _metricChineseNames[key] ?? key;
                        return DropdownMenuItem(
                          value: key,
                          child: Text(name),
                        );
                      }).toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => _metric = v);
                        }
                      },
                    ),
                  ),
                  const Divider(height: 1, color: AppColors.divider),
                  // Operator selector
                  _FieldRow(
                    label: '比较符',
                    child: DropdownButton<AlarmOperator>(
                      value: _operator,
                      dropdownColor: AppColors.cardBg,
                      underline: const SizedBox.shrink(),
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13),
                      items: AlarmOperator.values.map((op) {
                        return DropdownMenuItem(
                          value: op,
                          child:
                              Text(_operatorSymbol(op)),
                        );
                      }).toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => _operator = v);
                        }
                      },
                    ),
                  ),
                  const Divider(height: 1, color: AppColors.divider),
                  // Threshold
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(14, 0, 14, 0),
                    child: TextField(
                      controller: _thresholdCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(
                              decimal: true),
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14),
                      decoration: InputDecoration(
                        labelText: '阈值',
                        labelStyle: const TextStyle(
                            color: AppColors.textSecondary),
                        suffixText: _currentUnit,
                        suffixStyle: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 13),
                        errorText: _thresholdError,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(
                              color:
                                  AppColors.cyan.withAlpha(120)),
                        ),
                      ),
                    ),
                  ),
                  const Divider(height: 1, color: AppColors.divider),
                  // Sustain duration
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(14, 0, 14, 0),
                    child: TextField(
                      controller: _sustainCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14),
                      decoration: const InputDecoration(
                        labelText: '持续时间（秒，可选）',
                        labelStyle: TextStyle(
                            color: AppColors.textSecondary),
                        hintText: '留空表示立即触发',
                        hintStyle: TextStyle(
                            color: AppColors.textDim,
                            fontSize: 12),
                        suffixText: '秒',
                        suffixStyle: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 13),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(
                              color: AppColors.cyan),
                        ),
                      ),
                    ),
                  ),
                  const Divider(height: 1, color: AppColors.divider),
                  // Cooldown
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(14, 0, 14, 4),
                    child: TextField(
                      controller: _cooldownCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14),
                      decoration: const InputDecoration(
                        labelText: '冷却时间（分钟）',
                        labelStyle: TextStyle(
                            color: AppColors.textSecondary),
                        hintText: '5',
                        suffixText: '分钟',
                        suffixStyle: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 13),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(
                              color: AppColors.cyan),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Response ─────────────────────────────────────────────
            _SectionHeader(label: '响应方式'),
            const SizedBox(height: 10),
            _Card(
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 2),
                    title: const Text(
                      '应用内通知',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14),
                    ),
                    subtitle: const Text(
                      '在应用内显示告警横幅',
                      style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12),
                    ),
                    value: _respInApp,
                    activeColor: AppColors.cyan,
                    onChanged: (v) =>
                        setState(() => _respInApp = v),
                  ),
                  const Divider(height: 1, color: AppColors.divider),
                  SwitchListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 2),
                    title: const Text(
                      '声音提醒',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14),
                    ),
                    subtitle: const Text(
                      '触发告警音效',
                      style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12),
                    ),
                    value: _respSound,
                    activeColor: AppColors.cyan,
                    onChanged: (v) =>
                        setState(() => _respSound = v),
                  ),
                  const Divider(height: 1, color: AppColors.divider),
                  SwitchListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 2),
                    title: const Text(
                      'Discord 推送',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14),
                    ),
                    subtitle: const Text(
                      'Discord URL 在通知渠道中全局配置',
                      style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12),
                    ),
                    value: _respDiscord,
                    activeColor: AppColors.cyan,
                    onChanged: (v) =>
                        setState(() => _respDiscord = v),
                  ),
                  const Divider(height: 1, color: AppColors.divider),
                  // Snooze minutes
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                '暂停时长',
                                style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 14),
                              ),
                              SizedBox(height: 2),
                              Text(
                                '设为 0 表示不可暂停',
                                style: TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        DropdownButton<int>(
                          value: _snoozeMins,
                          dropdownColor: AppColors.cardBg,
                          underline: const SizedBox.shrink(),
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13),
                          items: [
                            const DropdownMenuItem(
                                value: 0,
                                child: Text('不可暂停')),
                            ...[5, 10, 15, 30, 60].map(
                              (m) => DropdownMenuItem(
                                value: m,
                                child: Text('$m 分钟'),
                              ),
                            ),
                          ],
                          onChanged: (v) {
                            if (v != null) {
                              setState(() => _snoozeMins = v);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // ── Save Button ──────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.cyan,
                  foregroundColor: AppColors.background,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                onPressed: _save,
                child: Text(
                  _isEditing ? '保存更改' : '创建规则',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ),

            // Delete button for non-builtin existing rules (duplicate of
            // AppBar action for visibility on longer forms)
            if (_isEditing && !isBuiltIn) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(
                        color: AppColors.danger, width: 0.8),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _delete,
                  child: const Text(
                    '删除规则',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small reusable widgets
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: AppColors.textMuted,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.5,
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: child,
    );
  }
}

class _FieldRow extends StatelessWidget {
  final String label;
  final Widget child;
  const _FieldRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          const Spacer(),
          child,
        ],
      ),
    );
  }
}
