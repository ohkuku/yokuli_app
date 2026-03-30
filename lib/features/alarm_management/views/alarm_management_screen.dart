import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/models/alarm.dart';
import '../../../core/models/alarm_rule.dart';
import '../../../core/providers/alarm_rule_provider.dart';
import '../../../core/theme/app_colors.dart';

// ---------------------------------------------------------------------------
// Helpers (shared with notifications screen)
// ---------------------------------------------------------------------------

String _typeLabel(AlarmType type) {
  switch (type) {
    case AlarmType.battery:
      return '电池低压';
    case AlarmType.depth:
      return '水深告警';
    case AlarmType.speed:
      return '航速告警';
    case AlarmType.mob:
      return 'MOB落水';
    case AlarmType.ais:
      return 'AIS碰撞';
    case AlarmType.solar:
      return '太阳能告警';
    case AlarmType.connection:
      return '连接告警';
  }
}

IconData _typeIcon(AlarmType type) {
  switch (type) {
    case AlarmType.battery:
      return Icons.battery_alert_rounded;
    case AlarmType.depth:
      return Icons.waves_rounded;
    case AlarmType.speed:
      return Icons.speed_rounded;
    case AlarmType.mob:
      return Icons.person_off_rounded;
    case AlarmType.ais:
      return Icons.radar_rounded;
    case AlarmType.solar:
      return Icons.wb_sunny_rounded;
    case AlarmType.connection:
      return Icons.link_off_rounded;
  }
}

// ---------------------------------------------------------------------------
// AlarmManagementScreen
// ---------------------------------------------------------------------------

class AlarmManagementScreen extends ConsumerWidget {
  const AlarmManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(alarmRuleProvider);
    final channelCfg = ref.watch(notifyChannelProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        title: const Text('告警管理',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Section 1: Alarm Rules ──────────────────────────────────
          _SectionHeader(label: 'ALARM RULES'),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: AppColors.cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border, width: 0.5),
            ),
            child: Column(
              children: AlarmType.values.map((type) {
                final rule = rules[type] ??
                    AlarmRuleConfig(
                        type: type,
                        channels: {NotifyChannel.inApp});
                final isLast = type == AlarmType.values.last;
                return Column(
                  children: [
                    _AlarmRuleRow(
                      rule: rule,
                      onTap: () => _showEditSheet(context, ref, rule),
                    ),
                    if (!isLast)
                      const Divider(
                          color: AppColors.divider, height: 1, indent: 16),
                  ],
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 24),

          // ── Section 2: Notification Channels ───────────────────────
          _SectionHeader(label: 'NOTIFICATION CHANNELS'),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: AppColors.cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border, width: 0.5),
            ),
            child: Column(
              children: [
                // Sound
                SwitchListTile(
                  activeColor: AppColors.cyan,
                  title: const Text('声音 / 震动',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500)),
                  subtitle: const Text('告警时触发系统提示音和震动',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
                  value: channelCfg.soundEnabled,
                  onChanged: (v) => ref
                      .read(notifyChannelProvider.notifier)
                      .update(channelCfg.copyWith(soundEnabled: v)),
                ),
                const Divider(
                    color: AppColors.divider, height: 1, indent: 16),
                // Discord
                SwitchListTile(
                  activeColor: AppColors.cyan,
                  title: const Text('Discord Webhook',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500)),
                  subtitle: const Text('发送告警到 Discord 频道',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
                  value: channelCfg.discordEnabled,
                  onChanged: (v) => ref
                      .read(notifyChannelProvider.notifier)
                      .update(channelCfg.copyWith(discordEnabled: v)),
                ),
                if (channelCfg.discordEnabled) ...[
                  const Divider(
                      color: AppColors.divider, height: 1, indent: 16),
                  _DiscordUrlField(channelCfg: channelCfg),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _showEditSheet(
      BuildContext context, WidgetRef ref, AlarmRuleConfig rule) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AlarmRuleEditSheet(rule: rule),
    );
  }
}

// ---------------------------------------------------------------------------
// Section header
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
          letterSpacing: 1.5),
    );
  }
}

// ---------------------------------------------------------------------------
// Alarm rule row
// ---------------------------------------------------------------------------

class _AlarmRuleRow extends ConsumerWidget {
  final AlarmRuleConfig rule;
  final VoidCallback onTap;

  const _AlarmRuleRow({required this.rule, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channels = rule.channels;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          color: AppColors.cyan.withOpacity(rule.enabled ? 0.15 : 0.05),
          border: Border.all(
              color: AppColors.cyan
                  .withOpacity(rule.enabled ? 0.3 : 0.1)),
        ),
        child: Icon(_typeIcon(rule.type),
            size: 18,
            color: rule.enabled
                ? AppColors.cyan
                : AppColors.textMuted),
      ),
      title: Text(
        _typeLabel(rule.type),
        style: TextStyle(
            color: rule.enabled
                ? AppColors.textPrimary
                : AppColors.textMuted,
            fontSize: 14,
            fontWeight: FontWeight.w500),
      ),
      subtitle: _buildChannelChips(channels),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            value: rule.enabled,
            activeColor: AppColors.cyan,
            onChanged: (v) => ref
                .read(alarmRuleProvider.notifier)
                .updateRule(rule.type, rule.copyWith(enabled: v)),
          ),
          const Icon(Icons.chevron_right_rounded,
              color: AppColors.textMuted, size: 18),
        ],
      ),
      onTap: onTap,
    );
  }

  Widget? _buildChannelChips(Set<NotifyChannel> channels) {
    if (channels.isEmpty) return null;
    return Wrap(
      spacing: 4,
      runSpacing: 2,
      children: channels.map((ch) {
        String label;
        IconData icon;
        switch (ch) {
          case NotifyChannel.inApp:
            label = '应用内';
            icon = Icons.notifications_rounded;
          case NotifyChannel.sound:
            label = '声音';
            icon = Icons.volume_up_rounded;
          case NotifyChannel.discord:
            label = 'Discord';
            icon = Icons.send_rounded;
        }
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.border,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 10, color: AppColors.textSecondary),
              const SizedBox(width: 3),
              Text(label,
                  style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.w500)),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Alarm rule edit sheet
// ---------------------------------------------------------------------------

class _AlarmRuleEditSheet extends ConsumerStatefulWidget {
  final AlarmRuleConfig rule;
  const _AlarmRuleEditSheet({required this.rule});

  @override
  ConsumerState<_AlarmRuleEditSheet> createState() =>
      _AlarmRuleEditSheetState();
}

class _AlarmRuleEditSheetState extends ConsumerState<_AlarmRuleEditSheet> {
  late bool _enabled;
  late Set<NotifyChannel> _channels;
  late int _snoozeMins;

  @override
  void initState() {
    super.initState();
    _enabled = widget.rule.enabled;
    _channels = Set.from(widget.rule.channels);
    _snoozeMins = widget.rule.snoozeMins;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: AppColors.inactive,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(_typeIcon(widget.rule.type),
                      size: 20, color: AppColors.cyan),
                  const SizedBox(width: 10),
                  Text(_typeLabel(widget.rule.type),
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 20),

              // Enable toggle
              Row(
                children: [
                  const Expanded(
                      child: Text('启用此告警',
                          style: TextStyle(
                              color: AppColors.textPrimary, fontSize: 14))),
                  Switch(
                    value: _enabled,
                    activeColor: AppColors.cyan,
                    onChanged: (v) => setState(() => _enabled = v),
                  ),
                ],
              ),
              const Divider(color: AppColors.border),
              const SizedBox(height: 8),

              // Channels
              const Text('通知渠道',
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8)),
              const SizedBox(height: 8),
              // In-App: always on, greyed
              _ChannelCheckRow(
                label: '应用内横幅',
                icon: Icons.notifications_rounded,
                checked: true,
                enabled: false,
                onChanged: null,
              ),
              _ChannelCheckRow(
                label: '声音 / 震动',
                icon: Icons.volume_up_rounded,
                checked: _channels.contains(NotifyChannel.sound),
                enabled: true,
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _channels.add(NotifyChannel.sound);
                  } else {
                    _channels.remove(NotifyChannel.sound);
                  }
                }),
              ),
              _ChannelCheckRow(
                label: 'Discord Webhook',
                icon: Icons.send_rounded,
                checked: _channels.contains(NotifyChannel.discord),
                enabled: true,
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _channels.add(NotifyChannel.discord);
                  } else {
                    _channels.remove(NotifyChannel.discord);
                  }
                }),
              ),
              const Divider(color: AppColors.border),
              const SizedBox(height: 8),

              // Snooze duration
              Row(
                children: [
                  const Expanded(
                      child: Text('暂停时长',
                          style: TextStyle(
                              color: AppColors.textPrimary, fontSize: 14))),
                  DropdownButton<int>(
                    value: _snoozeMins,
                    dropdownColor: AppColors.cardBg,
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 14),
                    underline: const SizedBox.shrink(),
                    items: [
                      const DropdownMenuItem(
                          value: 0, child: Text('不可暂停')),
                      ...[5, 10, 15, 30, 60].map((m) =>
                          DropdownMenuItem(
                              value: m, child: Text('$m 分钟'))),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _snoozeMins = v);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Save button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.cyan,
                    foregroundColor: AppColors.background,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _save,
                  child: const Text('保存',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _save() {
    // Ensure inApp is always present.
    final channels = {..._channels, NotifyChannel.inApp};
    ref.read(alarmRuleProvider.notifier).updateRule(
          widget.rule.type,
          widget.rule.copyWith(
            enabled: _enabled,
            channels: channels,
            snoozeMins: _snoozeMins,
          ),
        );
    Navigator.pop(context);
  }
}

class _ChannelCheckRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool checked;
  final bool enabled;
  final ValueChanged<bool?>? onChanged;

  const _ChannelCheckRow({
    required this.label,
    required this.icon,
    required this.checked,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        activeColor: AppColors.cyan,
        checkColor: AppColors.background,
        secondary: Icon(icon, size: 20, color: AppColors.textSecondary),
        title: Text(label,
            style: const TextStyle(
                color: AppColors.textPrimary, fontSize: 14)),
        value: checked,
        onChanged: enabled ? onChanged : null,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Discord URL field with test button
// ---------------------------------------------------------------------------

class _DiscordUrlField extends ConsumerStatefulWidget {
  final NotifyChannelConfig channelCfg;
  const _DiscordUrlField({required this.channelCfg});

  @override
  ConsumerState<_DiscordUrlField> createState() => _DiscordUrlFieldState();
}

class _DiscordUrlFieldState extends ConsumerState<_DiscordUrlField> {
  late final TextEditingController _controller;
  bool _testing = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    _controller =
        TextEditingController(text: widget.channelCfg.discordWebhookUrl);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            style: const TextStyle(
                color: AppColors.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              labelText: 'Discord Webhook URL',
              labelStyle:
                  const TextStyle(color: AppColors.textSecondary),
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    const BorderSide(color: AppColors.cyan),
              ),
              suffixIcon: IconButton(
                icon: const Icon(Icons.check_rounded,
                    color: AppColors.success),
                onPressed: _saveUrl,
              ),
            ),
            onSubmitted: (_) => _saveUrl(),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (_testResult != null)
                Expanded(
                  child: Text(
                    _testResult!,
                    style: TextStyle(
                      color: _testResult!.startsWith('✓')
                          ? AppColors.success
                          : AppColors.danger,
                      fontSize: 12,
                    ),
                  ),
                ),
              const Spacer(),
              TextButton(
                onPressed: _testing ? null : _sendTest,
                child: _testing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.cyan),
                      )
                    : const Text('发送测试',
                        style: TextStyle(color: AppColors.cyan)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _saveUrl() {
    ref.read(notifyChannelProvider.notifier).update(
          widget.channelCfg
              .copyWith(discordWebhookUrl: _controller.text.trim()),
        );
  }

  Future<void> _sendTest() async {
    final url = _controller.text.trim();
    if (url.isEmpty) return;
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final resp = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'content': '🔔 Yokuli 告警系统测试消息'}),
      );
      setState(() {
        _testResult = resp.statusCode < 300
            ? '✓ 发送成功 (${resp.statusCode})'
            : '✗ 发送失败 (${resp.statusCode})';
      });
    } catch (e) {
      setState(() => _testResult = '✗ 错误: $e');
    } finally {
      setState(() => _testing = false);
    }
  }
}
