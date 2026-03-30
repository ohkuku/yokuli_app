import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/providers/connection_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/vessel_provider.dart';
import '../../../core/services/signalk/signalk_client.dart';
import '../../../core/services/signalk/signalk_auth.dart';

class SignalKScreen extends ConsumerStatefulWidget {
  const SignalKScreen({super.key});

  @override
  ConsumerState<SignalKScreen> createState() => _SignalKScreenState();
}

class _SignalKScreenState extends ConsumerState<SignalKScreen> {
  late final TextEditingController _hostCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _userCtrl;
  late final TextEditingController _passCtrl;

  bool _connecting  = false;
  bool _obscurePass = true;
  String? _connectError;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);

    // Pre-populate host/port from saved settings; fall back to parsing legacy URL
    String initialHost = s.signalKHost;
    int initialPort = s.signalKPort;
    if (initialHost.isEmpty && s.signalKUrl.isNotEmpty) {
      try {
        final uri = Uri.parse(s.signalKUrl);
        initialHost = uri.host;
        if (uri.port > 0) initialPort = uri.port;
      } catch (_) {}
    }

    _hostCtrl = TextEditingController(text: initialHost);
    _portCtrl = TextEditingController(text: initialPort.toString());
    _userCtrl = TextEditingController(text: s.signalKUsername);
    _passCtrl = TextEditingController(text: s.signalKPassword);
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  // ── Connect (auto-auth if credentials filled) ─────────────────────────────

  Future<void> _connect() async {
    final host = _hostCtrl.text.trim();
    final port = int.tryParse(_portCtrl.text.trim()) ?? 3000;
    final user = _userCtrl.text.trim();
    final pass = _passCtrl.text;
    if (host.isEmpty) return;

    final url = 'ws://$host:$port/signalk/v1/stream';
    setState(() { _connecting = true; _connectError = null; });

    String? token;

    // Step 1: login if credentials are provided
    if (user.isNotEmpty && pass.isNotEmpty) {
      try {
        token = await SignalKAuth.login(url, user, pass);
        await ref.read(settingsProvider.notifier).update(
          ref.read(settingsProvider).copyWith(
            signalKHost:     host,
            signalKPort:     port,
            signalKUsername: user,
            signalKPassword: pass,
            signalKToken:    token,
          ),
        );
      } on SignalKAuthException catch (e) {
        if (mounted) setState(() { _connecting = false; _connectError = e.message; });
        return;
      } catch (e) {
        if (mounted) setState(() { _connecting = false; _connectError = e.toString(); });
        return;
      }
    } else {
      // No credentials entered — use saved token if available
      final saved = ref.read(settingsProvider);
      token = saved.hasToken ? saved.signalKToken : null;
      await ref.read(settingsProvider.notifier).update(
        saved.copyWith(signalKHost: host, signalKPort: port),
      );
    }

    // Step 2: open WebSocket (with token if we have one)
    await ref.read(signalKClientProvider).connect(url, token: token);
    if (mounted) setState(() => _connecting = false);
  }

  Future<void> _disconnect() async {
    await ref.read(signalKClientProvider).disconnect();
    ref.read(vesselProvider.notifier).reset();
  }

  Future<void> _forgetCredentials() async {
    await ref.read(settingsProvider.notifier).update(
      ref.read(settingsProvider).copyWith(
        signalKUsername: '',
        signalKToken:    '',
      ),
    );
    _userCtrl.clear();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final conn     = ref.watch(connectionProvider);
    final vessel   = ref.watch(vesselProvider);
    final settings = ref.watch(settingsProvider);
    final skStatus = conn.signalK;
    final connected = skStatus == ConnectionStatus.connected;

    // Client role: data comes from LAN host, direct SK config not needed
    if (settings.deviceRole == DeviceRole.client) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('Signal K Hub')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.wifi_rounded, size: 48, color: AppColors.teal),
                SizedBox(height: 16),
                Text(
                  '客户端模式',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 8),
                Text(
                  '当前设备为从端，Signal K 数据由主机通过局域网同步。\n如需直连 Signal K，请在设置中切换为独立或主机模式。',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Signal K Hub')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Status card
            _StatusCard(status: skStatus, error: conn.signalKError),
            const SizedBox(height: 20),

            // ── Server ────────────────────────────────────────────────
            _SectionHeader('SERVER'),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _hostCtrl,
                    enabled: !connected,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Host IP',
                      hintText: '192.168.1.10',
                      prefixIcon: Icon(Icons.dns_rounded),
                    ),
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    textInputAction: TextInputAction.next,
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: _portCtrl,
                    enabled: !connected,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Port',
                      hintText: '3000',
                    ),
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Authentication (optional) ─────────────────────────────
            _SectionHeader('AUTHENTICATION  (leave blank if not required)'),
            const SizedBox(height: 8),

            if (settings.hasToken && !connected)
              // Saved token banner — show who is logged in
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.cyan.withAlpha(15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.cyan.withAlpha(50)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.key_rounded,
                        color: AppColors.cyan, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Saved token for ${settings.signalKUsername}',
                        style: const TextStyle(
                            color: AppColors.cyan, fontSize: 12),
                      ),
                    ),
                    TextButton(
                      onPressed: _forgetCredentials,
                      style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 0)),
                      child: const Text('Forget',
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 12)),
                    ),
                  ],
                ),
              ),

            if (!connected) ...[
              TextField(
                controller: _userCtrl,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  prefixIcon: Icon(Icons.person_rounded),
                ),
                autocorrect: false,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _passCtrl,
                obscureText: _obscurePass,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_rounded),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePass
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded),
                    color: AppColors.textMuted,
                    onPressed: () =>
                        setState(() => _obscurePass = !_obscurePass),
                  ),
                ),
                onSubmitted: (_) => _connect(),
              ),
            ],

            if (connected && settings.signalKUsername.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(Icons.verified_user_rounded,
                        color: AppColors.success, size: 14),
                    const SizedBox(width: 6),
                    Text('Authenticated as ${settings.signalKUsername}',
                        style: const TextStyle(
                            color: AppColors.success, fontSize: 12)),
                  ],
                ),
              ),

            if (_connectError != null) ...[
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.error_outline_rounded,
                    size: 14, color: AppColors.danger),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(_connectError!,
                      style: const TextStyle(
                          color: AppColors.danger, fontSize: 12)),
                ),
              ]),
            ],

            const SizedBox(height: 16),

            // ── Single Connect / Disconnect button ────────────────────
            if (connected)
              OutlinedButton.icon(
                onPressed: _disconnect,
                icon: const Icon(Icons.link_off_rounded,
                    color: AppColors.danger),
                label: const Text('Disconnect',
                    style: TextStyle(color: AppColors.danger)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.danger),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              )
            else
              ElevatedButton.icon(
                onPressed: _connecting ? null : _connect,
                icon: _connecting
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.background))
                    : const Icon(Icons.link_rounded),
                label: Text(_connecting ? 'Connecting…' : 'Connect'),
                style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48)),
              ),

            const SizedBox(height: 28),

            // ── Live data (when connected) ────────────────────────────
            if (connected) ...[
              _SectionHeader('LIVE DATA'),
              const SizedBox(height: 8),
              _DataTable(vessel: vessel),
              const SizedBox(height: 24),
            ],

            // ── Options ───────────────────────────────────────────────
            _SectionHeader('OPTIONS'),
            const SizedBox(height: 8),
            _ToggleTile(
              title: 'Auto-connect on start',
              subtitle:
                  'Connect to Signal K automatically when app launches',
              value: settings.autoConnectSignalK,
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .update(settings.copyWith(autoConnectSignalK: v)),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  final ConnectionStatus status;
  final String? error;
  const _StatusCard({required this.status, this.error});

  @override
  Widget build(BuildContext context) {
    final (color, icon, label) = switch (status) {
      ConnectionStatus.connected =>
        (AppColors.success, Icons.check_circle_rounded, 'Connected'),
      ConnectionStatus.connecting =>
        (AppColors.warning, Icons.sync_rounded, 'Connecting…'),
      ConnectionStatus.error =>
        (AppColors.danger, Icons.error_rounded, 'Error'),
      ConnectionStatus.disconnected =>
        (AppColors.inactive, Icons.radio_button_unchecked, 'Disconnected'),
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        color: color,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
                if (error != null)
                  Text(error!,
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DataTable extends StatelessWidget {
  final vessel;
  const _DataTable({required this.vessel});

  @override
  Widget build(BuildContext context) {
    final rows = [
      ('SOG', vessel.speedOverGround?.toStringAsFixed(2), 'kn'),
      ('COG', vessel.courseOverGround?.toStringAsFixed(1), '°'),
      ('HDG', vessel.heading?.toStringAsFixed(1), '°'),
      ('TWS', vessel.trueWindSpeed?.toStringAsFixed(1), 'kn'),
      ('TWD', vessel.trueWindDirection?.toStringAsFixed(0), '°'),
      ('AWS', vessel.apparentWindSpeed?.toStringAsFixed(1), 'kn'),
      ('AWA', vessel.apparentWindAngle?.toStringAsFixed(0), '°'),
      ('DBK', vessel.depthBelowKeel?.toStringAsFixed(1), 'm'),
      ('LAT', vessel.position?.latitude.toStringAsFixed(6), ''),
      ('LON', vessel.position?.longitude.toStringAsFixed(6), ''),
    ];
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: rows.asMap().entries.map((e) {
          final (label, value, unit) = e.value;
          return Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: e.key < rows.length - 1
                ? const BoxDecoration(
                    border: Border(
                        bottom: BorderSide(color: AppColors.divider)))
                : null,
            child: Row(
              children: [
                SizedBox(
                  width: 44,
                  child: Text(label,
                      style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5)),
                ),
                Expanded(
                  child: Text(
                    value != null ? '$value $unit'.trim() : '—',
                    style: TextStyle(
                      color: value != null
                          ? AppColors.textPrimary
                          : AppColors.textDim,
                      fontSize: 13,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
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
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5));
}

class _ToggleTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _ToggleTile(
      {required this.title,
      required this.subtitle,
      required this.value,
      required this.onChanged});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: SwitchListTile(
          title: Text(title),
          subtitle: Text(subtitle),
          value: value,
          onChanged: onChanged,
          activeColor: AppColors.cyan,
        ),
      );
}
