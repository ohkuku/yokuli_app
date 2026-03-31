import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/connection_provider.dart';
import '../../../core/providers/locale_provider.dart';
import '../../../core/providers/device_provider.dart' show DeviceInfo, deviceProvider;
import '../../../core/services/lan_sync/lan_sync_service.dart';
import '../../../core/services/lan_sync/lan_sync_platform_base.dart' show DiscoveredHost;
import '../../../core/services/lan_sync/lan_sync_service.dart' show syncCursorStatusProvider;
import '../../../core/sync/sync_cursor_store.dart' show SyncCollections;

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late TextEditingController _nameCtrl;
  late TextEditingController _hostIpCtrl;
  late TextEditingController _hostPortCtrl;

  List<DiscoveredHost> _scannedHosts = [];
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
      _scannedHosts = [];
    });
    final subnet = _localIp!.substring(0, _localIp!.lastIndexOf('.'));
    final hosts = await ref.read(lanSyncServiceProvider).scanForHosts(subnet);
    if (mounted) setState(() {
      _scannedHosts = hosts;
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
    // Sync name + settings to all LAN peers immediately
    ref.read(lanSyncServiceProvider).broadcastSettings();
    if (mounted) {
      final s = ref.read(stringsProvider);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.settingsSaved)));
    }
  }

  Future<void> _connectToDiscoveredHost(DiscoveredHost host) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        title: Text(host.name,
            style: const TextStyle(color: AppColors.textPrimary)),
        content: Text(
          host.ws,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('连接',
                style: TextStyle(color: AppColors.cyan, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // Save host settings
    final newSettings = ref.read(settingsProvider).copyWith(
          hostIp: host.host,
          hostPort: host.port,
        );
    await ref.read(settingsProvider.notifier).update(newSettings);
    _hostIpCtrl.text = host.host;
    _hostPortCtrl.text = host.port.toString();

    // Connect
    final svc = ref.read(lanSyncServiceProvider);
    if (ref.read(connectionProvider).isLanSyncActive) {
      await svc.restart();
    } else {
      await svc.start();
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已连接到 ${host.name}')),
      );
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

  Future<void> _forceFullResync() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        title: const Text('强制全量重同步',
            style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          '将清除所有同步游标，下次连接时重新同步全部数据。',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.warning),
            child: const Text('重置并重连'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(lanSyncServiceProvider).forceFullResync();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('同步游标已重置，正在重新连接…')),
      );
    }
  }

  void _showSyncDiagnostics(Map<String, String> cursors) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg,
        title: const Text('同步诊断',
            style: TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('各集合最后同步时间（本地游标）：',
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
              const SizedBox(height: 8),
              ...SyncCollections.all.map((col) {
                final cursor = cursors[col];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(col,
                            style: const TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 11,
                                fontFamily: 'monospace')),
                      ),
                      Text(
                        cursor != null
                            ? cursor.substring(0, 19).replaceFirst('T', ' ')
                            : '—',
                        style: TextStyle(
                          color: cursor != null
                              ? AppColors.textSecondary
                              : AppColors.inactive,
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final settings = ref.watch(settingsProvider);
    final conn = ref.watch(connectionProvider);
    ref.watch(lanSyncServiceProvider); // ensure provider is alive
    final device = ref.watch(deviceProvider);
    final discoveredPeers = ref.watch(discoveredPeersProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(s.settings),
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
            _SectionHeader(s.language.toUpperCase()),
            const SizedBox(height: 8),
            _LanguageSelector(),
            const SizedBox(height: 24),

            // --- Vessel ---
            _SectionHeader(s.sectionVessel),
            const SizedBox(height: 8),
            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                labelText: s.vesselNameLabel,
                prefixIcon: const Icon(Icons.directions_boat_rounded),
              ),
              onEditingComplete: _save,
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 24),

            // --- LAN Sync ---
            _SectionHeader(s.lanSync.toUpperCase()),
            const SizedBox(height: 8),

            // Server info (native, when active)
            if (!kIsWeb && conn.isLanSyncActive) ...[
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
                    Row(children: [
                      const Icon(Icons.router_rounded, size: 16, color: AppColors.cyan),
                      const SizedBox(width: 6),
                      Text(s.thisDeviceServing,
                          style: const TextStyle(
                              color: AppColors.cyan,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                    ]),
                    const SizedBox(height: 8),
                    Text(
                      'ws://${_localIp ?? '…'}:${settings.hostPort}',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Connected peers: ${conn.peerCount}  ·  '
                      'Device ID: ${device.deviceId.substring(0, 8)}',
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],

            // Port config (native only)
            if (!kIsWeb) ...[
              // Discovered peers (auto-found via UDP)
              if (discoveredPeers.isNotEmpty) ...[
                Text(s.discoveredOnNetwork,
                    style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2)),
                const SizedBox(height: 6),
                ...discoveredPeers.map((h) => _DiscoveredHostTile(
                      host: h,
                      onConnect: () => _connectToDiscoveredHost(h),
                    )),
                const SizedBox(height: 8),
              ],

              // Manual scan fallback
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
                    label: Text(_scanning ? s.scanning : s.scanSubnet),
                  ),
                ),
              ]),
              if (_scannedHosts.isNotEmpty) ...[
                const SizedBox(height: 8),
                ..._scannedHosts.map((h) => _DiscoveredHostTile(
                      host: h,
                      onConnect: () => _connectToDiscoveredHost(h),
                    )),
              ],
            ] else ...[
              // Web: manual IP entry only
              TextField(
                controller: _hostIpCtrl,
                decoration: const InputDecoration(
                  labelText: '主机 IP 地址',
                  hintText: '192.168.1.100',
                  prefixIcon: Icon(Icons.wifi_rounded),
                ),
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.next,
                onEditingComplete: _save,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _hostPortCtrl,
                decoration: const InputDecoration(
                  labelText: '主机端口',
                  hintText: '8765',
                  prefixIcon: Icon(Icons.lan_rounded),
                ),
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                onEditingComplete: _save,
              ),
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
                      'Enter the IP of a native device manually. '
                      'Auto-discovery is not available in browsers.',
                      style: TextStyle(
                          color: AppColors.textMuted, fontSize: 12),
                    ),
                  ),
                ]),
              ),
            ],

            const SizedBox(height: 24),

            // --- Sync Status ---
            _SectionHeader('SYNC STATUS'),
            const SizedBox(height: 8),
            _SyncStatusPanel(
              onForceResync: _forceFullResync,
              onShowDiagnostics: _showSyncDiagnostics,
            ),
            const SizedBox(height: 24),

            // --- Devices ---
            _SectionHeader(s.sectionDevices),
            const SizedBox(height: 8),
            _DevicesPanel(
              device: device,
              peers: discoveredPeers,
              peerCount: conn.peerCount,
            ),
            const SizedBox(height: 24),

            // --- Display ---
            _SectionHeader(s.sectionDisplay),
            const SizedBox(height: 8),
            _ToggleTile(
              title: s.keepScreenOn,
              value: settings.keepScreenOn,
              onChanged: (v) async {
                await ref
                    .read(settingsProvider.notifier)
                    .update(settings.copyWith(keepScreenOn: v));
                ref.read(lanSyncServiceProvider).broadcastSettings();
              },
            ),
            const SizedBox(height: 24),

            // --- About ---
            _SectionHeader(s.about),
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

class _DiscoveredHostTile extends StatelessWidget {
  final DiscoveredHost host;
  final VoidCallback onConnect;
  const _DiscoveredHostTile({required this.host, required this.onConnect});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onConnect,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.cyan.withAlpha(15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.cyan.withAlpha(50)),
        ),
        child: Row(
          children: [
            const Icon(Icons.device_hub_rounded, color: AppColors.cyan, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(host.name,
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                  Text(host.ws,
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 11)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.cyan.withAlpha(40),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('连接',
                  style: TextStyle(
                      color: AppColors.cyan,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

class _LanConnectButton extends ConsumerStatefulWidget {
  final AppConnectionState conn;
  const _LanConnectButton({required this.conn});

  @override
  ConsumerState<_LanConnectButton> createState() => _LanConnectButtonState();
}

class _LanConnectButtonState extends ConsumerState<_LanConnectButton> {
  bool _loading = false;

  Future<void> _toggle() async {
    setState(() => _loading = true);
    try {
      final svc = ref.read(lanSyncServiceProvider);
      if (widget.conn.isLanSyncActive) {
        await svc.stop();
      } else {
        await svc.start();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isActive = widget.conn.isLanSyncActive;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: isActive
              ? AppColors.danger.withAlpha(200)
              : AppColors.cyan.withAlpha(220),
          foregroundColor: isActive ? Colors.white : AppColors.background,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        onPressed: _loading ? null : _toggle,
        icon: _loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(isActive ? Icons.wifi_off_rounded : Icons.wifi_rounded,
                size: 20),
        label: Text(
          isActive ? 'DISCONNECT' : 'CONNECT LAN',
          style:
              const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.5),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Devices Panel
// ---------------------------------------------------------------------------

class _DevicesPanel extends StatelessWidget {
  final DeviceInfo device;
  final List<DiscoveredHost> peers;
  final int peerCount;

  const _DevicesPanel({
    required this.device,
    required this.peers,
    required this.peerCount,
  });

  String _fmtSv(int svMs) {
    if (svMs == 0) return '—';
    final dt = DateTime.fromMillisecondsSinceEpoch(svMs);
    final mo = dt.month.toString().padLeft(2, '0');
    final d  = dt.day.toString().padLeft(2, '0');
    final h  = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    final s  = dt.second.toString().padLeft(2, '0');
    return '$mo-$d $h:$mi:$s';
  }

  @override
  Widget build(BuildContext context) {
    final ownSvMs = device.stateVersion.millisecondsSinceEpoch;
    final ownIdShort = device.deviceId.length >= 8
        ? device.deviceId.substring(0, 8)
        : device.deviceId;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          // Header row
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                const Icon(Icons.devices_rounded,
                    size: 15, color: AppColors.cyan),
                const SizedBox(width: 6),
                const Text('设备信息',
                    style: TextStyle(
                        color: AppColors.cyan,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
                const Spacer(),
                if (peerCount > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.teal.withAlpha(40),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '$peerCount 台设备连入',
                      style: const TextStyle(
                          color: AppColors.teal,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.divider),
          // Own device row
          _DeviceRow(
            label: '本机  $ownIdShort',
            svLabel: _fmtSv(ownSvMs),
            isOwn: true,
          ),
          // Peer rows
          ...peers.asMap().entries.map((e) {
            final h = e.value;
            final idShort = h.deviceId.isEmpty
                ? h.host
                : h.deviceId.length >= 8
                    ? h.deviceId.substring(0, 8)
                    : h.deviceId;
            return Column(
              children: [
                const Divider(height: 1, color: AppColors.divider),
                _DeviceRow(
                  label: '${h.name}  $idShort',
                  svLabel: _fmtSv(h.stateVersionMs),
                  isOwn: false,
                ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sync Status Panel
// ---------------------------------------------------------------------------

class _SyncStatusPanel extends ConsumerWidget {
  final VoidCallback onForceResync;
  final void Function(Map<String, String>) onShowDiagnostics;

  const _SyncStatusPanel({
    required this.onForceResync,
    required this.onShowDiagnostics,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cursorsAsync = ref.watch(syncCursorStatusProvider);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(children: [
              const Icon(Icons.sync_rounded, size: 15, color: AppColors.cyan),
              const SizedBox(width: 6),
              const Text('数据同步',
                  style: TextStyle(
                      color: AppColors.cyan,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              cursorsAsync.when(
                loading: () => const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.5)),
                error: (_, __) => const SizedBox.shrink(),
                data: (cursors) {
                  final synced = cursors.values.where((v) => v.isNotEmpty).length;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: synced > 0
                          ? AppColors.teal.withAlpha(40)
                          : AppColors.inactive.withAlpha(40),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '$synced / ${SyncCollections.all.length} 已同步',
                      style: TextStyle(
                          color: synced > 0
                              ? AppColors.teal
                              : AppColors.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                  );
                },
              ),
            ]),
          ),
          const Divider(height: 1, color: AppColors.divider),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onForceResync,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('强制重同步', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.warning,
                    side: const BorderSide(color: AppColors.warning),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: cursorsAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (cursors) => OutlinedButton.icon(
                    onPressed: () => onShowDiagnostics(cursors),
                    icon: const Icon(Icons.info_outline_rounded, size: 16),
                    label: const Text('诊断日志', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      side: const BorderSide(color: AppColors.border),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  final String label;
  final String svLabel;
  final bool isOwn;

  const _DeviceRow({
    required this.label,
    required this.svLabel,
    required this.isOwn,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(
            isOwn ? Icons.smartphone_rounded : Icons.tablet_rounded,
            size: 15,
            color: isOwn ? AppColors.cyan : AppColors.textMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color:
                    isOwn ? AppColors.textPrimary : AppColors.textSecondary,
                fontSize: 12,
                fontWeight: isOwn ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          Text(
            svLabel,
            style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }
}
