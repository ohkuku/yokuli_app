import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/locale_provider.dart';
import '../../../core/l10n/strings.dart' show S;
import '../../../core/providers/device_provider.dart' show deviceProvider;
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
  late TextEditingController _deviceNameCtrl;
  late TextEditingController _vesselNameCtrl;
  late TextEditingController _hostIpCtrl; // web only: manual host address
  String? _localIp;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    _deviceNameCtrl = TextEditingController(text: s.deviceName);
    _vesselNameCtrl = TextEditingController(text: s.vesselName);
    _hostIpCtrl = TextEditingController(text: s.hostIp);
    if (!kIsWeb) _loadLocalIp();
  }

  @override
  void dispose() {
    _deviceNameCtrl.dispose();
    _vesselNameCtrl.dispose();
    _hostIpCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLocalIp() async {
    final ip = await ref.read(lanSyncServiceProvider).getLocalIp();
    if (mounted) setState(() => _localIp = ip);
  }

  /// Save this device's name and restart LAN sync so the new name is broadcast.
  Future<void> _saveDeviceName() async {
    final name = _deviceNameCtrl.text.trim();
    if (name.isEmpty) return;
    await ref.read(settingsProvider.notifier).update(
          ref.read(settingsProvider).copyWith(deviceName: name),
        );
    await ref.read(lanSyncServiceProvider).restart();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('设备名已更新')));
    }
  }

  /// Save vessel name and broadcast to all peers.
  Future<void> _saveVesselName() async {
    await ref.read(settingsProvider.notifier).update(
          ref.read(settingsProvider).copyWith(
                vesselName: _vesselNameCtrl.text.trim(),
              ),
        );
    ref.read(lanSyncServiceProvider).broadcastSettings();
    if (mounted) {
      final s = ref.read(stringsProvider);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.settingsSaved)));
    }
  }

  /// Web only: save the manual host address.
  Future<void> _saveHostIp() async {
    await ref.read(settingsProvider.notifier).update(
          ref.read(settingsProvider).copyWith(hostIp: _hostIpCtrl.text.trim()),
        );
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('主机地址已保存')));
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

            // --- This Device ---
            _SectionHeader(s.sectionThisDevice),
            const SizedBox(height: 8),
            _ThisDeviceCard(
              deviceNameCtrl: _deviceNameCtrl,
              deviceId: device.deviceId,
              localIp: _localIp,
              onSave: _saveDeviceName,
            ),
            const SizedBox(height: 24),

            // --- Vessel ---
            _SectionHeader(s.sectionVessel),
            const SizedBox(height: 8),
            TextField(
              controller: _vesselNameCtrl,
              decoration: InputDecoration(
                labelText: s.vesselNameLabel,
                prefixIcon: const Icon(Icons.directions_boat_rounded),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.check_rounded),
                  onPressed: _saveVesselName,
                  tooltip: s.settingsSaved,
                ),
              ),
              onEditingComplete: _saveVesselName,
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 24),

            // Web: manual host address (no port exposed)
            if (kIsWeb) ...[
              _SectionHeader('HOST ADDRESS'),
              const SizedBox(height: 8),
              TextField(
                controller: _hostIpCtrl,
                decoration: const InputDecoration(
                  labelText: '主机地址',
                  hintText: '192.168.1.100',
                  prefixIcon: Icon(Icons.wifi_rounded),
                  helperText: '输入运行 Yokuli 的设备 IP 地址',
                ),
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                onEditingComplete: _saveHostIp,
              ),
              const SizedBox(height: 24),
            ],

            // --- LAN Devices ---
            _SectionHeader(s.sectionLanDevices),
            const SizedBox(height: 8),
            _LanDevicesPanel(peers: discoveredPeers),
            const SizedBox(height: 24),

            // --- Sync Status ---
            _SectionHeader('SYNC STATUS'),
            const SizedBox(height: 8),
            _SyncStatusPanel(
              onForceResync: _forceFullResync,
              onShowDiagnostics: _showSyncDiagnostics,
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

// ---------------------------------------------------------------------------
// This Device Card
// ---------------------------------------------------------------------------

class _ThisDeviceCard extends ConsumerWidget {
  final TextEditingController deviceNameCtrl;
  final String deviceId;
  final String? localIp;
  final VoidCallback onSave;

  const _ThisDeviceCard({
    required this.deviceNameCtrl,
    required this.deviceId,
    required this.localIp,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: TextField(
              controller: deviceNameCtrl,
              decoration: InputDecoration(
                labelText: s.deviceNameLabel,
                hintText: s.deviceNameHint,
                prefixIcon: const Icon(Icons.smartphone_rounded),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.check_rounded),
                  onPressed: onSave,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: UnderlineInputBorder(
                  borderSide:
                      BorderSide(color: AppColors.cyan.withAlpha(120)),
                ),
              ),
              onEditingComplete: onSave,
              textInputAction: TextInputAction.done,
            ),
          ),
          const Divider(height: 1, color: AppColors.divider),
          _InfoRow(
            icon: Icons.fingerprint_rounded,
            label: s.deviceIdLabel,
            value: deviceId.length >= 8 ? deviceId.substring(0, 8) : deviceId,
          ),
          if (!kIsWeb && localIp != null) ...[
            const Divider(height: 1, color: AppColors.divider),
            _InfoRow(
              icon: Icons.lan_rounded,
              label: 'IP',
              value: localIp!,
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Text(label,
              style: const TextStyle(
                  color: AppColors.textMuted, fontSize: 12)),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// LAN Devices Panel
// ---------------------------------------------------------------------------

class _LanDevicesPanel extends ConsumerWidget {
  final List<DiscoveredHost> peers;

  const _LanDevicesPanel({required this.peers});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    if (peers.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.wifi_off_rounded,
                size: 16, color: AppColors.textMuted),
            const SizedBox(width: 10),
            Text(s.noOtherDevices,
                style: const TextStyle(
                    color: AppColors.textMuted, fontSize: 13)),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: peers.asMap().entries.map((e) {
          final isFirst = e.key == 0;
          final isLast = e.key == peers.length - 1;
          return Column(
            children: [
              if (!isFirst) const Divider(height: 1, color: AppColors.divider),
              _PeerDeviceTile(
                host: e.value,
                isFirst: isFirst,
                isLast: isLast,
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _PeerDeviceTile extends ConsumerWidget {
  final DiscoveredHost host;
  final bool isFirst;
  final bool isLast;

  const _PeerDeviceTile({
    required this.host,
    required this.isFirst,
    required this.isLast,
  });

  void _showDetail(BuildContext context, S s) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _DeviceDetailSheet(host: host, s: s),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final borderRadius = BorderRadius.vertical(
      top: isFirst ? const Radius.circular(12) : Radius.zero,
      bottom: isLast ? const Radius.circular(12) : Radius.zero,
    );
    return InkWell(
      onTap: () => _showDetail(context, s),
      borderRadius: borderRadius,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.cyan.withAlpha(20),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.tablet_rounded,
                  size: 18, color: AppColors.cyan),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    host.name,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    host.host,
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textMuted, size: 18),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Device Detail Bottom Sheet
// ---------------------------------------------------------------------------

class _DeviceDetailSheet extends StatelessWidget {
  final DiscoveredHost host;
  final S s;

  const _DeviceDetailSheet({required this.host, required this.s});

  String _fmtSv(int svMs) {
    if (svMs == 0) return '—';
    final dt = DateTime.fromMillisecondsSinceEpoch(svMs);
    final mo = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    final sec = dt.second.toString().padLeft(2, '0');
    return '$mo-$d $h:$mi:$sec';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Title
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.cyan.withAlpha(20),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.tablet_rounded,
                    color: AppColors.cyan, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(host.name,
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w700)),
                    Text(s.deviceDetailTitle,
                        style: const TextStyle(
                            color: AppColors.textMuted, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(color: AppColors.divider),
          const SizedBox(height: 8),
          _DetailRow(
              icon: Icons.lan_rounded, label: 'IP', value: host.host),
          if (host.deviceId.isNotEmpty) ...[
            const SizedBox(height: 8),
            _DetailRow(
              icon: Icons.fingerprint_rounded,
              label: s.deviceIdLabel,
              value: host.deviceId.length >= 8
                  ? host.deviceId.substring(0, 8)
                  : host.deviceId,
            ),
          ],
          const SizedBox(height: 8),
          _DetailRow(
            icon: Icons.update_rounded,
            label: '最后同步',
            value: _fmtSv(host.stateVersionMs),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: AppColors.textMuted),
        const SizedBox(width: 10),
        Text(label,
            style: const TextStyle(
                color: AppColors.textMuted, fontSize: 12)),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontFamily: 'monospace'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Web Banner
// ---------------------------------------------------------------------------

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
                  'Client — connect to a Host running on a native (Android/iOS) device.',
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

// ---------------------------------------------------------------------------
// Shared small widgets
// ---------------------------------------------------------------------------

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
          _LangBtn(
              code: 'en',
              label: '🇬🇧  English',
              selected: lang == 'en',
              onTap: () => ref.read(localeProvider.notifier).setLanguage('en')),
          Container(width: 1, height: 44, color: AppColors.border),
          _LangBtn(
              code: 'zh',
              label: '🇨🇳  中文',
              selected: lang == 'zh',
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
  const _LangBtn(
      {required this.code,
      required this.label,
      required this.selected,
      required this.onTap});

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
                  final synced =
                      cursors.values.where((v) => v.isNotEmpty).length;
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
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
                  label:
                      const Text('强制重同步', style: TextStyle(fontSize: 12)),
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
                    icon:
                        const Icon(Icons.info_outline_rounded, size: 16),
                    label:
                        const Text('诊断日志', style: TextStyle(fontSize: 12)),
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
