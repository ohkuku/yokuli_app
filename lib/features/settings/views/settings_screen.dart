import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/connection_provider.dart';
import '../../../core/services/lan_sync/lan_sync_service.dart';
import '../../../core/services/lan_sync/sync_client.dart';
import '../../../core/services/lan_sync/sync_host.dart';

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
    _loadLocalIp();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _hostIpCtrl.dispose();
    _hostPortCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLocalIp() async {
    final ip = await SyncHost.getLocalIp();
    if (mounted) setState(() => _localIp = ip);
  }

  Future<void> _scanForHosts() async {
    if (_localIp == null) return;
    setState(() {
      _scanning = true;
      _discoveredHosts = [];
    });
    final subnet = _localIp!.substring(0, _localIp!.lastIndexOf('.'));
    final hosts = await HostDiscovery.scanSubnet(subnet: subnet);
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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Settings saved')));
    }
  }

  Future<void> _restartLanSync() async {
    await ref.read(lanSyncServiceProvider).restart();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('LAN sync restarted')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final conn = ref.watch(connectionProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
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

            // Role selector
            _RoleSelector(
              current: settings.deviceRole,
              onChanged: (role) => ref
                  .read(settingsProvider.notifier)
                  .update(settings.copyWith(deviceRole: role)),
            ),
            const SizedBox(height: 12),

            // Host info (when role=host)
            if (settings.deviceRole == DeviceRole.host) ...[
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
                      Text('This device is hosting',
                          style: TextStyle(
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
                      'Connected peers: ${conn.connectedPeers.length}',
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

            // Client config (when role=client)
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
              const SizedBox(height: 10),

              // Scan button
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
            ],

            const SizedBox(height: 12),

            // Auto-connect LAN
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
                label: const Text('Restart LAN sync'),
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
                  Text('v1.0.0',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleSelector extends StatelessWidget {
  final DeviceRole current;
  final ValueChanged<DeviceRole> onChanged;

  const _RoleSelector({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: DeviceRole.values.map((role) {
          final (icon, title, desc) = switch (role) {
            DeviceRole.standalone => (
                Icons.smartphone_rounded,
                'Standalone',
                'Direct Signal K connection, no sync'
              ),
            DeviceRole.host => (
                Icons.router_rounded,
                'Host (Master)',
                'Aggregates data, serves peers on LAN'
              ),
            DeviceRole.client => (
                Icons.tablet_rounded,
                'Client',
                'Receives data from host device'
              ),
          };
          final isLast = role == DeviceRole.values.last;
          return InkWell(
            onTap: () => onChanged(role),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                border: isLast
                    ? null
                    : const Border(bottom: BorderSide(color: AppColors.divider)),
              ),
              child: Row(children: [
                Icon(icon,
                    color: current == role ? AppColors.cyan : AppColors.textMuted,
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
                  const Icon(Icons.check_rounded, color: AppColors.cyan, size: 18),
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
