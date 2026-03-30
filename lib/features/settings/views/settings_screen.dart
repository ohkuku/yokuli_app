import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/connection_provider.dart';
import '../../../core/providers/locale_provider.dart';
import '../../../core/providers/device_provider.dart' show DeviceInfo, deviceProvider;
import '../../../core/services/lan_sync/lan_sync_service.dart';
import '../../../core/services/lan_sync/lan_sync_platform_base.dart' show DiscoveredHost;
import '../../../core/services/data_export_service.dart';
import '../../../core/services/signalk/signalk_auth.dart';
import '../../../core/services/signalk/signalk_client.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late TextEditingController _nameCtrl;
  late TextEditingController _hostIpCtrl;
  late TextEditingController _hostPortCtrl;
  late TextEditingController _skHostCtrl;
  late TextEditingController _skPortCtrl;
  late TextEditingController _skUserCtrl;
  late TextEditingController _skPassCtrl;

  List<DiscoveredHost> _scannedHosts = [];
  bool _scanning = false;
  bool _exporting = false;
  bool _skConnecting = false;
  String? _skConnectError;
  String? _localIp;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    _nameCtrl = TextEditingController(text: s.vesselName);
    _hostIpCtrl = TextEditingController(text: s.hostIp);
    _hostPortCtrl = TextEditingController(text: s.hostPort.toString());
    _skHostCtrl = TextEditingController(text: s.signalKHost);
    _skPortCtrl = TextEditingController(text: s.signalKPort.toString());
    _skUserCtrl = TextEditingController(text: s.signalKUsername);
    _skPassCtrl = TextEditingController(text: s.signalKPassword);
    if (!kIsWeb) _loadLocalIp();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _hostIpCtrl.dispose();
    _hostPortCtrl.dispose();
    _skHostCtrl.dispose();
    _skPortCtrl.dispose();
    _skUserCtrl.dispose();
    _skPassCtrl.dispose();
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

  Future<void> _exportData() async {
    if (kIsWeb) {
      final jsonStr = ref.read(dataExportServiceProvider).exportAsJsonString();
      if (!mounted) return;
      final s = ref.read(stringsProvider);
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(s.exportBackup),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '复制以下 JSON 以保存备份。',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Container(
                height: 150,
                decoration: BoxDecoration(
                  color: AppColors.cardBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(8),
                  child: SelectableText(
                    jsonStr,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 10),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: jsonStr));
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(s.copy == '复制' ? '已复制到剪贴板' : 'Copied to clipboard')),
                );
              },
              child: Text(s.copy),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(s.close),
            ),
          ],
        ),
      );
      return;
    }

    setState(() => _exporting = true);
    try {
      await ref.read(dataExportServiceProvider).exportAndShare();
    } catch (e) {
      if (mounted) {
        final s = ref.read(stringsProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${s.exportBackup} failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _importData() async {
    final s = ref.read(stringsProvider);
    final ctrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(s.importBackup),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.importBackup == '导入备份'
                  ? '这将替换所有本地数据。请先导出以保留备份。'
                  : 'This will REPLACE all local data. Export first to keep a backup.',
              style: const TextStyle(
                  color: AppColors.warning,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              maxLines: 8,
              decoration: InputDecoration(
                hintText: s.importBackup == '导入备份' ? '在此粘贴 JSON 备份…' : 'Paste JSON backup here…',
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(s.importBackup),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    final json = ctrl.text.trim();
    if (json.isEmpty) return;

    try {
      await ref.read(dataExportServiceProvider).importFromJsonString(json);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.importSuccess)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${s.importSuccess == '导入成功' ? '导入失败' : 'Import failed'}: $e')),
        );
      }
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

  Future<void> _saveSkSettings() async {
    final host = _skHostCtrl.text.trim();
    final port = int.tryParse(_skPortCtrl.text.trim()) ?? 3000;
    final username = _skUserCtrl.text.trim();
    final password = _skPassCtrl.text;
    await ref.read(settingsProvider.notifier).update(
          ref.read(settingsProvider).copyWith(
                signalKHost: host,
                signalKPort: port,
                signalKUsername: username,
                signalKPassword: password,
              ),
        );
  }

  Future<void> _connectSK() async {
    await _saveSkSettings();
    final settings = ref.read(settingsProvider);
    final url = settings.effectiveSignalKUrl;
    if (url.isEmpty) return;

    setState(() {
      _skConnecting = true;
      _skConnectError = null;
    });
    try {
      String? token;
      if (settings.hasCredentials) {
        try {
          token = await SignalKAuth.login(
            url,
            settings.signalKUsername,
            settings.signalKPassword,
          );
        } catch (_) {}
      }
      await ref.read(signalKClientProvider).connect(url, token: token);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Signal K 已连接')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _skConnectError = '连接失败：$e');
    } finally {
      if (mounted) setState(() => _skConnecting = false);
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

            // --- Signal K ---
            const SizedBox(height: 24),
            _SectionHeader('SIGNAL K'),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _skHostCtrl,
                    decoration: const InputDecoration(
                      labelText: '主机 / 地址',
                      hintText: '192.168.1.10',
                      prefixIcon: Icon(Icons.dns_rounded),
                    ),
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    textInputAction: TextInputAction.next,
                    onEditingComplete: _saveSkSettings,
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 90,
                  child: TextField(
                    controller: _skPortCtrl,
                    decoration: const InputDecoration(labelText: '端口'),
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    onEditingComplete: _saveSkSettings,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _skUserCtrl,
              decoration: const InputDecoration(
                labelText: '用户名',
                prefixIcon: Icon(Icons.person_rounded),
              ),
              autocorrect: false,
              textInputAction: TextInputAction.next,
              onEditingComplete: _saveSkSettings,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _skPassCtrl,
              decoration: const InputDecoration(
                labelText: '密码',
                prefixIcon: Icon(Icons.lock_rounded),
              ),
              obscureText: true,
              textInputAction: TextInputAction.done,
              onEditingComplete: _saveSkSettings,
            ),
            if (_skConnectError != null) ...[
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.error_outline_rounded,
                    size: 14, color: AppColors.danger),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(_skConnectError!,
                      style: const TextStyle(
                          color: AppColors.danger, fontSize: 12)),
                ),
              ]),
            ],
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _skConnecting ? null : _connectSK,
                icon: _skConnecting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.background),
                      )
                    : const Icon(Icons.link_rounded),
                label: Text(_skConnecting ? '连接中…' : '连接 Signal K'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.cyan,
                  foregroundColor: AppColors.background,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),

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

            // --- Data Management ---
            _SectionHeader(s.sectionDataMgmt),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _exporting ? null : _exportData,
                    icon: _exporting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload_rounded),
                    label: Text(_exporting ? 'Exporting…' : s.exportBackup),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _importData,
                    icon: const Icon(Icons.download_rounded),
                    label: Text(s.importBackup),
                  ),
                ),
              ],
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
