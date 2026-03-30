import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/providers/connection_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/vessel_provider.dart';
import '../../../core/providers/locale_provider.dart';
import '../../../core/services/signalk/signalk_client.dart';
import '../../../core/services/signalk/signalk_auth.dart';
import '../../../core/services/lan_sync/lan_sync_service.dart';

/// Strip scheme, embedded port, and path from a host string.
(String, int) _parseHostPort(String raw, int defaultPort) {
  var s = raw.trim();
  if (s.isEmpty) return ('', defaultPort);
  s = s.replaceFirst(RegExp(r'^(wss?|https?)://'), '');
  final slash = s.indexOf('/');
  if (slash >= 0) s = s.substring(0, slash);
  final q = s.indexOf('?');
  if (q >= 0) s = s.substring(0, q);
  int port = defaultPort;
  if (!s.startsWith('[')) {
    final colon = s.lastIndexOf(':');
    if (colon > 0) {
      final maybePort = int.tryParse(s.substring(colon + 1));
      if (maybePort != null && maybePort > 0 && maybePort < 65536) {
        port = maybePort;
        s = s.substring(0, colon);
      }
    }
  }
  return (s.trim(), port);
}

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

  bool _saving = false;
  bool _obscurePass = true;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
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

  // ── Save & connect ─────────────────────────────────────────────────────────

  Future<void> _saveAndConnect() async {
    final rawHost = _hostCtrl.text.trim();
    final rawPort = int.tryParse(_portCtrl.text.trim()) ?? 3000;
    final (host, port) = _parseHostPort(rawHost, rawPort);
    if (host.isEmpty) return;

    if (host != rawHost) _hostCtrl.text = host;
    if (port != rawPort) _portCtrl.text = '$port';

    final user = _userCtrl.text.trim();
    final pass = _passCtrl.text;
    final url = 'ws://$host:$port/signalk/v1/stream?subscribe=all';

    setState(() {
      _saving = true;
      _saveError = null;
    });

    String? token;
    if (user.isNotEmpty && pass.isNotEmpty) {
      try {
        token = await SignalKAuth.login(url, user, pass);
      } on SignalKAuthException catch (e) {
        if (mounted) setState(() { _saving = false; _saveError = e.message; });
        return;
      } catch (e) {
        if (mounted) setState(() { _saving = false; _saveError = e.toString(); });
        return;
      }
    }

    await ref.read(settingsProvider.notifier).update(
          ref.read(settingsProvider).copyWith(
                signalKHost: host,
                signalKPort: port,
                signalKUsername: user,
                signalKPassword: pass,
              ),
        );

    // Disconnect existing connection first, then reconnect
    await ref.read(signalKClientProvider).disconnect();
    await ref.read(signalKClientProvider).connect(url, token: token);

    // Broadcast updated credentials + settings to LAN peers
    ref.read(lanSyncServiceProvider).broadcastSettings();

    if (mounted) setState(() => _saving = false);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final conn = ref.watch(connectionProvider);
    final vessel = ref.watch(vesselProvider);
    final settings = ref.watch(settingsProvider);
    final skStatus = conn.signalK;
    final connected = skStatus == ConnectionStatus.connected;
    final s = ref.watch(stringsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('Signal K Hub'),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Status card
            _StatusCard(status: skStatus, error: conn.signalKError),
            const SizedBox(height: 20),

            // ── Server config ──────────────────────────────────────────
            _SectionHeader('服务器'),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _hostCtrl,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                    decoration: InputDecoration(
                      labelText: s.signalKHostLabel,
                      hintText: s.signalKHostHint,
                      prefixIcon: const Icon(Icons.dns_rounded),
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
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                    decoration: InputDecoration(
                      labelText: s.signalKPortLabel,
                      hintText: '3000',
                    ),
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Auth ──────────────────────────────────────────────────
            _SectionHeader('认证（可选）'),
            const SizedBox(height: 8),
            TextField(
              controller: _userCtrl,
              decoration: const InputDecoration(
                labelText: '用户名',
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
                labelText: '密码',
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
              onSubmitted: (_) => _saveAndConnect(),
            ),

            if (connected && settings.signalKUsername.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.verified_user_rounded,
                      color: AppColors.success, size: 14),
                  const SizedBox(width: 6),
                  Text('已认证: ${settings.signalKUsername}',
                      style: const TextStyle(
                          color: AppColors.success, fontSize: 12)),
                ],
              ),
            ],

            if (_saveError != null) ...[
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.error_outline_rounded,
                    size: 14, color: AppColors.danger),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(_saveError!,
                      style: const TextStyle(
                          color: AppColors.danger, fontSize: 12)),
                ),
              ]),
            ],

            const SizedBox(height: 20),

            // ── Save & connect button ─────────────────────────────────
            ElevatedButton.icon(
              onPressed: _saving ? null : _saveAndConnect,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.background))
                  : const Icon(Icons.link_rounded),
              label: Text(_saving
                  ? '连接中…'
                  : connected
                      ? '重新连接'
                      : '保存并连接'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor:
                    connected ? AppColors.teal : AppColors.cyan,
                foregroundColor: AppColors.background,
              ),
            ),

            const SizedBox(height: 28),

            // ── Live data ─────────────────────────────────────────────
            if (connected) ...[
              _SectionHeader('实时数据'),
              const SizedBox(height: 8),
              _DataTable(vessel: vessel),
              const SizedBox(height: 24),
            ],
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
        (AppColors.success, Icons.check_circle_rounded, '已连接'),
      ConnectionStatus.connecting =>
        (AppColors.warning, Icons.sync_rounded, '连接中…'),
      ConnectionStatus.error =>
        (AppColors.danger, Icons.error_rounded, '连接错误'),
      ConnectionStatus.disconnected =>
        (AppColors.inactive, Icons.radio_button_unchecked, '未连接'),
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
