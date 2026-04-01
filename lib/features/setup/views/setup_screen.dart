import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/lan_sync/lan_sync_service.dart';

/// Full-screen setup screen shown when:
/// 1. A new device joins the LAN (all devices navigate here).
/// 2. First launch if MetService API key is missing.
///
/// Existing devices see their current config + confirm.
/// New devices fill in device name; MetService token syncs from peer.
/// Both finish independently then go to home.
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  late final TextEditingController _deviceNameCtrl;
  late final TextEditingController _metKeyCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    _deviceNameCtrl = TextEditingController(text: s.deviceName);
    _metKeyCtrl = TextEditingController(text: s.metServiceApiKey);
  }

  @override
  void dispose() {
    _deviceNameCtrl.dispose();
    _metKeyCtrl.dispose();
    super.dispose();
  }

  bool get _canFinish =>
      _deviceNameCtrl.text.trim().isNotEmpty &&
      _metKeyCtrl.text.trim().isNotEmpty;

  Future<void> _finish() async {
    if (!_canFinish || _saving) return;
    setState(() => _saving = true);

    final s = ref.read(settingsProvider);
    final now = DateTime.now().toUtc();
    final metKeyChanged = _metKeyCtrl.text.trim() != s.metServiceApiKey;

    await ref.read(settingsProvider.notifier).update(
          s.copyWith(
            deviceName: _deviceNameCtrl.text.trim(),
            metServiceApiKey: _metKeyCtrl.text.trim(),
            metServiceApiKeyUpdatedAt: metKeyChanged
                ? now
                : s.metServiceApiKeyUpdatedAt,
          ),
        );

    if (mounted) {
      setState(() => _saving = false);
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final peers = ref.watch(discoveredPeersProvider);
    final peerCount = peers.length;
    // Listen for MetService key updates from peers so the field stays current.
    ref.listen(settingsProvider.select((s) => s.metServiceApiKey), (_, key) {
      if (key.isNotEmpty && _metKeyCtrl.text.trim().isEmpty) {
        _metKeyCtrl.text = key;
        setState(() {});
      }
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  const Icon(Icons.sailing_rounded,
                      size: 52, color: AppColors.cyan),
                  const SizedBox(height: 16),
                  const Text(
                    '设备配置',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (peerCount > 0)
                    _PeerBadge(count: peerCount + 1)
                  else
                    const Text(
                      '完成配置后进入应用',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 13),
                    ),
                  const SizedBox(height: 36),

                  // Device name field
                  _FieldLabel('设备名称', required: true),
                  const SizedBox(height: 8),
                  _TextField(
                    controller: _deviceNameCtrl,
                    hint: '例如：舵手平板',
                    icon: Icons.smartphone_rounded,
                    onChanged: (_) => setState(() {}),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 24),

                  // MetService key field
                  _FieldLabel('MetService API Key', required: true),
                  const SizedBox(height: 4),
                  const Text(
                    'data.metservice.com 开发者密钥 — 新西兰最准确的天气数据',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  _TextField(
                    controller: _metKeyCtrl,
                    hint: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
                    icon: Icons.key_rounded,
                    onChanged: (_) => setState(() {}),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _finish(),
                  ),
                  if (peerCount > 0) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.sync_rounded,
                            size: 13, color: AppColors.cyan),
                        const SizedBox(width: 6),
                        Text(
                          _metKeyCtrl.text.isNotEmpty
                              ? '已从网络同步'
                              : '等待从其他设备同步…',
                          style: const TextStyle(
                              color: AppColors.cyan,
                              fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 40),

                  // Finish button
                  _FinishButton(
                    enabled: _canFinish,
                    saving: _saving,
                    onPressed: _finish,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small widgets
// ---------------------------------------------------------------------------

class _PeerBadge extends StatelessWidget {
  final int count;
  const _PeerBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.cyan.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cyan.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.devices_rounded,
              size: 13, color: AppColors.cyan),
          const SizedBox(width: 6),
          Text(
            '有 $count 台设备在线',
            style: const TextStyle(
                color: AppColors.cyan,
                fontSize: 12,
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String label;
  final bool required;
  const _FieldLabel(this.label, {this.required = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (required) ...[
          const SizedBox(width: 4),
          const Text('*',
              style: TextStyle(color: AppColors.danger, fontSize: 14)),
        ],
      ],
    );
  }
}

class _TextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final ValueChanged<String>? onChanged;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  const _TextField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.onChanged,
    this.textInputAction,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textMuted),
        prefixIcon: Icon(icon, color: AppColors.textMuted),
      ),
      autocorrect: false,
      onChanged: onChanged,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
    );
  }
}

class _FinishButton extends StatelessWidget {
  final bool enabled;
  final bool saving;
  final VoidCallback onPressed;

  const _FinishButton({
    required this.enabled,
    required this.saving,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: enabled && !saving ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.cyan,
          foregroundColor: AppColors.background,
          disabledBackgroundColor: AppColors.cyan.withOpacity(0.3),
        ),
        child: saving
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: AppColors.background),
              )
            : const Text('完成',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
