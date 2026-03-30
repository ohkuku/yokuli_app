import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/connection_provider.dart';
import '../../../core/providers/locale_provider.dart';
import '../../../core/services/lan_sync/lan_sync_service.dart';
import '../../../core/services/lan_sync/lan_sync_platform_base.dart' show DiscoveredHost;

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late TextEditingController _nameCtrl;
  late TextEditingController _hostIpCtrl;
  late TextEditingController _hostPortCtrl;

  List<DiscoveredHost> _discoveredHosts = [];
  bool _scanning = false;
  String? _localIp;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    _nameCtrl = TextEditingController(text: s.vesselName);
    _hostIpCtrl = TextEditingController(text: s.hostIp);
    _hostPortCtrl = TextEditingController(text: s.hostPort.toString());
    if (!kIsWeb) _loadLocalIp();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _hostIpCtrl.dispose();
    _hostPortCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLocalIp() async {
    final ip = await ref.read(lanSyncServiceProvider).getLocalIp();
    if (mounted) setState(() => _localIp = ip);
  }

  Future<void> _scanForHosts() async {
    if (_localIp == null) return;
    setState(() {
      _scanning = true;
      _discoveredHosts = [];
    });
    final subnet = _localIp!.substring(0, _localIp!.lastIndexOf('.'));
    final hosts = await ref.read(lanSyncServiceProvider).scanForHosts(subnet);
    if (mounted) setState(() {
      _discoveredHosts = hosts;
      _scanning = false;
    });
  }

  Future<void> _save() async {
    final port = int.tryParse(_hostPortCtrl.text.trim()) ?? 8765;
    await ref.read(settingsProvider.notifier).update(
          ref.read(settingsProvider).copyWith(
                vesselName: _nameCtrl.text.trim(),
                hostIp: _hostIpCtrl.text.trim(),
                hostPort: port,
              ),
        );
    if (mounted) {
      final s = ref.read(stringsProvider);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.settingsSaved)));
    }
  }

  Future<void> _restartLanSync() async {
    await ref.read(lanSyncServiceProvider).restart();
    if (mounted) {
      final s = ref.read(stringsProvider);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.lanSyncRestarted)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final conn = ref.watch(connectionProvider);
    final lanService = ref.watch(lanSyncServiceProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(ref.watch(stringsProvider).settings),
        actions: [
          TextButton(onPressed: _save, child: Text(ref.watch(stringsProvider).save)),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Web platform banner
            if (kIsWeb) ...[
              _WebBanner(),
              const SizedBox(height: 16),
            ],

            // --- Language ---
            _SectionHeader('LANGUAGE'),
            const SizedBox(height: 8),
            _LanguageSelector(),
            const SizedBox(height: 24),

            // --- Vessel ---
            _SectionHeader('VESSEL'),
            const SizedBox(height: 8),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Vessel name',
                prefixIcon: Icon(Icons.directions_boat_rounded),
              ),
            ),
            const SizedBox(height: 24),

            // --- LAN Sync ---
            _SectionHeader('LAN SYNC'),
            const SizedBox(height: 8),

            // Role selector — web only shows Standalone / Client
            _RoleSelector(
              current: settings.deviceRole,
              canBeHost: lanService.canBeHost,
              onChanged: (role) => ref
                  .read(settingsProvider.notifier)
                  .update(settings.copyWith(deviceRole: role)),
            ),
            const SizedBox(height: 12),

            // Host info card (native + host role only)
            if (!kIsWeb && settings.deviceRole == DeviceRole.host) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.cyan.withAlpha(15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.cyan.withAlpha(50)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      Icon(Icons.router_rounded, size: 16, color: AppColors.cyan),
                      SizedBox(width: 6),
                      Text(ref.watch(stringsProvider).hostingStatus,
                          style: const TextStyle(
                              color: AppColors.cyan,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                    ]),
                    const SizedBox(height: 8),
                    Text(
                      'Other devices connect to:\nws://${_localIp ?? '…'}:${settings.hostPort}',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Connected peers: ${conn.peerCount}',
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _hostPortCtrl,
                decoration: const InputDecoration(
                  labelText: 'Host port',
                  hintText: '8765',
                  prefixIcon: Icon(Icons.lan_rounded),
                ),
                keyboardType: TextInputType.number,
              ),
            ],

            // Client config
            if (settings.deviceRole == DeviceRole.client) ...[
              TextField(
                controller: _hostIpCtrl,
                decoration: const InputDecoration(
                  labelText: 'Host IP address',
                  hintText: '192.168.1.100',
                  prefixIcon: Icon(Icons.wifi_rounded),
                ),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _hostPortCtrl,
                decoration: const InputDecoration(
                  labelText: 'Host port',
                  hintText: '8765',
                  prefixIcon: Icon(Icons.lan_rounded),
                ),
                keyboardType: TextInputType.number,
              ),
              // Scan button (native only)
              if (!kIsWeb) ...[
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _scanning ? null : _scanForHosts,
                      icon: _scanning
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.search_rounded),
                      label: Text(_scanning ? 'Scanning…' : 'Scan for hosts'),
                    ),
                  ),
                ]),
                if (_discoveredHosts.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ...(_discoveredHosts.map((h) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.device_hub_rounded,
                            color: AppColors.cyan),
                        title: Text(h.name),
                        subtitle: Text(h.ws),
                        onTap: () {
                          _hostIpCtrl.text = h.host;
                          _hostPortCtrl.text = h.port.toString();
                        },
                      ))),
                ],
              ] else ...[
                // Web: manual IP only, no scan
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(children: [
                    Icon(Icons.info_outline_rounded,
                        size: 14, color: AppColors.textMuted),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Enter the IP of the Host device manually. '
                        'Auto-discovery is not available in browsers.',
                        style: TextStyle(
                            color: AppColors.textMuted, fontSize: 12),
                      ),
                    ),
                  ]),
                ),
              ],
            ],

            const SizedBox(height: 12),

            _ToggleTile(
              title: 'Auto-start LAN sync on launch',
              value: settings.autoConnectLan,
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .update(settings.copyWith(autoConnectLan: v)),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _restartLanSync,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(ref.watch(stringsProvider).restartLanSync),
              ),
            ),
            const SizedBox(height: 24),

            // --- Display ---
            _SectionHeader('DISPLAY'),
            const SizedBox(height: 8),
            _ToggleTile(
              title: 'Keep screen on',
              value: settings.keepScreenOn,
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .update(settings.copyWith(keepScreenOn: v)),
            ),
            const SizedBox(height: 24),

            // --- About ---
            _SectionHeader('ABOUT'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.cardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Yokuli',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  const Text('Vessel Control Platform',
                      style: TextStyle(color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  Row(children: [
                    const Text('v1.0.0  ·  ',
                        style:
                            TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    Text(
                      kIsWeb ? 'Web' : 'Native',
                      style: TextStyle(
                        color: kIsWeb ? AppColors.modWeather : AppColors.cyan,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Banner shown only on web explaining platform limitations
class _WebBanner extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.modWeather.withAlpha(20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.modWeather.withAlpha(60)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.public_rounded, color: AppColors.modWeather, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.webModeLabel,
                    style: const TextStyle(
                        color: AppColors.modWeather,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                const Text(
                  'Browsers cannot run a server. This device can only act as a '
                  'Client — connect to a Host running on a native (Android/iOS) device. '
                  'Signal K direct connection works normally.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleSelector extends StatelessWidget {
  final DeviceRole current;
  final bool canBeHost;
  final ValueChanged<DeviceRole> onChanged;

  const _RoleSelector({
    required this.current,
    required this.canBeHost,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final roles = DeviceRole.values.where((r) {
      // Hide Host option on web
      if (!canBeHost && r == DeviceRole.host) return false;
      return true;
    }).toList();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: roles.asMap().entries.map((entry) {
          final isLast = entry.key == roles.length - 1;
          final role = entry.value;
          final (icon, title, desc) = switch (role) {
            DeviceRole.standalone => (
                Icons.smartphone_rounded,
                'Standalone',
                'Direct Signal K connection, no LAN sync',
              ),
            DeviceRole.host => (
                Icons.router_rounded,
                'Host (Master)',
                'Aggregates data, serves peers on LAN',
              ),
            DeviceRole.client => (
                Icons.tablet_rounded,
                'Client',
                'Receives all data from a Host device',
              ),
          };
          return InkWell(
            onTap: () => onChanged(role),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                border: isLast
                    ? null
                    : const Border(
                        bottom: BorderSide(color: AppColors.divider)),
              ),
              child: Row(children: [
                Icon(icon,
                    color: current == role
                        ? AppColors.cyan
                        : AppColors.textMuted,
                    size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                              color: current == role
                                  ? AppColors.textPrimary
                                  : AppColors.textSecondary,
                              fontWeight: FontWeight.w500)),
                      Text(desc,
                          style: const TextStyle(
                              color: AppColors.textMuted, fontSize: 12)),
                    ],
                  ),
                ),
                if (current == role)
                  const Icon(Icons.check_rounded,
                      color: AppColors.cyan, size: 18),
              ]),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
        ),
      );
}

class _ToggleTile extends StatelessWidget {
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleTile({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: SwitchListTile(
          title: Text(title),
          value: value,
          onChanged: onChanged,
          activeColor: AppColors.cyan,
        ),
      );
}

class _LanguageSelector extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(localeProvider);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          _LangBtn(code: 'en', label: '🇬🇧  English', selected: lang == 'en',
              onTap: () => ref.read(localeProvider.notifier).setLanguage('en')),
          Container(width: 1, height: 44, color: AppColors.border),
          _LangBtn(code: 'zh', label: '🇨🇳  中文', selected: lang == 'zh',
              onTap: () => ref.read(localeProvider.notifier).setLanguage('zh')),
        ],
      ),
    );
  }
}

class _LangBtn extends StatelessWidget {
  final String code;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _LangBtn({required this.code, required this.label,
      required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            color: selected ? AppColors.cyan.withAlpha(25) : Colors.transparent,
            borderRadius: code == 'en'
                ? const BorderRadius.horizontal(left: Radius.circular(12))
                : const BorderRadius.horizontal(right: Radius.circular(12)),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: selected ? AppColors.cyan : AppColors.textMuted,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}
