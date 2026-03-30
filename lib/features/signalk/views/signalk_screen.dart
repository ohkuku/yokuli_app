import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/providers/connection_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/vessel_provider.dart';
import '../../../core/services/signalk/signalk_client.dart';

class SignalKScreen extends ConsumerStatefulWidget {
  const SignalKScreen({super.key});

  @override
  ConsumerState<SignalKScreen> createState() => _SignalKScreenState();
}

class _SignalKScreenState extends ConsumerState<SignalKScreen> {
  late final TextEditingController _urlController;
  bool _connecting = false;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _urlController = TextEditingController(text: settings.signalKUrl);
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    // Save URL
    await ref
        .read(settingsProvider.notifier)
        .update(ref.read(settingsProvider).copyWith(signalKUrl: url));

    setState(() => _connecting = true);
    await ref.read(signalKClientProvider).connect(url);
    if (mounted) setState(() => _connecting = false);
  }

  Future<void> _disconnect() async {
    await ref.read(signalKClientProvider).disconnect();
    ref.read(vesselProvider.notifier).reset();
  }

  String _wsToHttp(String ws) =>
      ws.replaceFirst('ws://', 'http://').replaceFirst('wss://', 'https://');

  @override
  Widget build(BuildContext context) {
    final conn = ref.watch(connectionProvider);
    final vessel = ref.watch(vesselProvider);
    final skStatus = conn.signalK;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Signal K Hub')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Status card
            _StatusCard(status: skStatus, error: conn.signalKError),
            const SizedBox(height: 16),

            // Connection form
            _SectionHeader('SERVER'),
            const SizedBox(height: 8),
            TextField(
              controller: _urlController,
              enabled: skStatus != ConnectionStatus.connected,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
              decoration: const InputDecoration(
                labelText: 'WebSocket URL',
                hintText: 'ws://192.168.1.10:3000/signalk/v1/stream',
                prefixIcon: Icon(Icons.link_rounded),
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
              onSubmitted: (_) => _connect(),
            ),
            const SizedBox(height: 8),
            Text(
              'Tip: Signal K default port is 3000. REST API: ${_wsToHttp(_urlController.text).replaceFirst('/stream', '')}',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
            const SizedBox(height: 16),

            // Connect / disconnect button
            if (skStatus == ConnectionStatus.connected)
              OutlinedButton.icon(
                onPressed: _disconnect,
                icon: const Icon(Icons.link_off_rounded, color: AppColors.danger),
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
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.background,
                        ),
                      )
                    : const Icon(Icons.link_rounded),
                label: Text(_connecting ? 'Connecting…' : 'Connect'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),

            const SizedBox(height: 24),

            // Live data preview (when connected)
            if (skStatus == ConnectionStatus.connected) ...[
              _SectionHeader('LIVE DATA PREVIEW'),
              const SizedBox(height: 8),
              _DataTable(vessel: vessel),
              const SizedBox(height: 24),
            ],

            // Auto-connect toggle
            _SectionHeader('OPTIONS'),
            const SizedBox(height: 8),
            _ToggleTile(
              title: 'Auto-connect on start',
              subtitle: 'Connect to Signal K automatically when app launches',
              value: ref.watch(settingsProvider).autoConnectSignalK,
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .update(ref.read(settingsProvider).copyWith(autoConnectSignalK: v)),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final ConnectionStatus status;
  final String? error;

  const _StatusCard({required this.status, this.error});

  @override
  Widget build(BuildContext context) {
    final (color, icon, label) = switch (status) {
      ConnectionStatus.connected => (AppColors.success, Icons.check_circle_rounded, 'Connected'),
      ConnectionStatus.connecting => (AppColors.warning, Icons.sync_rounded, 'Connecting…'),
      ConnectionStatus.error => (AppColors.danger, Icons.error_rounded, 'Error'),
      ConnectionStatus.disconnected => (AppColors.inactive, Icons.radio_button_unchecked, 'Disconnected'),
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
                        color: color, fontSize: 15, fontWeight: FontWeight.w600)),
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
        children: rows.asMap().entries.map((entry) {
          final i = entry.key;
          final (label, value, unit) = entry.value;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              border: i < rows.length - 1
                  ? const Border(bottom: BorderSide(color: AppColors.divider))
                  : null,
            ),
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
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
}
