import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/providers/locale_provider.dart';
import '../../core/providers/device_provider.dart';
import '../../core/providers/voyage_provider.dart';
import '../../core/providers/task_provider.dart';
import '../../core/providers/issue_provider.dart';
import '../../core/providers/log_provider.dart';
import '../../core/providers/alarm_rule_provider.dart';
import '../../core/providers/alarm_instance_provider.dart';
import '../../core/providers/alarm_action_provider.dart';
import '../../core/services/alarm_evaluator.dart';
import '../../core/services/signalk/signalk_auth.dart';
import '../../core/services/signalk/signalk_client.dart';
import '../../core/services/lan_sync/lan_sync_service.dart';
import '../../core/sync/sync_migration.dart';
import '../../features/mob/providers/mob_provider.dart';
import '../../features/mob/services/mob_watcher_service.dart';
import '../../core/services/telemetry_service.dart';
import '../safety/providers/safety_provider.dart';

// ---------------------------------------------------------------------------
// Startup screen
// ---------------------------------------------------------------------------

enum _Phase { loading, ready, wizard }

class StartupScreen extends ConsumerStatefulWidget {
  final VoidCallback onComplete;
  const StartupScreen({required this.onComplete, super.key});

  @override
  ConsumerState<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends ConsumerState<StartupScreen>
    with SingleTickerProviderStateMixin {
  _Phase _phase = _Phase.loading;

  // Loading step statuses (index → done?)
  final List<bool> _steps = [false, false, false, false];
  int _peersFound = 0;
  String _currentStep = '初始化…';
  bool _skConnected = false;

  // Wizard
  int _wizardPage = 0;
  final _pageCtrl = PageController();
  final _deviceNameCtrl = TextEditingController();
  final _vesselNameCtrl = TextEditingController();
  final _skHostCtrl = TextEditingController();
  final _skPortCtrl = TextEditingController(text: '3000');
  final _skUserCtrl = TextEditingController();
  final _skPassCtrl = TextEditingController();
  bool _wizardConnecting = false;
  String? _wizardError;

  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    // Run init async; use addPostFrameCallback so providers are available
    WidgetsBinding.instance.addPostFrameCallback((_) => _runInit());
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _pageCtrl.dispose();
    _deviceNameCtrl.dispose();
    _vesselNameCtrl.dispose();
    _skHostCtrl.dispose();
    _skPortCtrl.dispose();
    _skUserCtrl.dispose();
    _skPassCtrl.dispose();
    super.dispose();
  }

  // ── Init sequence ──────────────────────────────────────────────────────────

  Future<void> _runInit() async {
    // Step 0: Load local data
    _setStep('加载本地数据…');
    try {
      await _loadLocalData().timeout(const Duration(seconds: 30));
    } catch (e) {
      // Non-fatal: log and continue — defaults are already in providers.
      debugPrint('[Startup] _loadLocalData error: $e');
    }
    _markStep(0);

    // Step 1: Start LAN sync (always on native)
    if (!kIsWeb) {
      _setStep('启动局域网同步…');
      await ref.read(lanSyncServiceProvider).start();
      _markStep(1);

      // Step 2: Peer discovery window (8 s — UDP broadcast is every 5 s)
      _setStep('搜索设备中…');
      const searchDuration = Duration(seconds: 8);
      const tick = Duration(milliseconds: 500);
      var elapsed = Duration.zero;
      while (elapsed < searchDuration) {
        await Future.delayed(tick);
        elapsed += tick;
        final found = ref.read(discoveredPeersProvider).length;
        if (mounted) setState(() => _peersFound = found);
      }
      _markStep(2);
    } else {
      _markStep(1);
      _markStep(2);
    }

    // Step 3: Connect Signal K if configured
    // Re-read settings here: LAN sync may have updated them from a peer.
    final latestSettings = ref.read(settingsProvider);
    final url = latestSettings.effectiveSignalKUrl;
    if (url.isNotEmpty) {
      _setStep('连接 Signal K…');
      await _connectSK(latestSettings);
      _markStep(3);
    } else {
      _markStep(3);
    }

    if (!mounted) return;

    // Decide: first-time wizard or go straight to app.
    // Wizard is shown only when device has no name yet.
    final isFirstTime = latestSettings.deviceName.isEmpty;

    if (isFirstTime) {
      setState(() {
        _currentStep = '欢迎使用';
        _phase = _Phase.wizard;
      });
    } else {
      _setStep('准备就绪');
      setState(() => _phase = _Phase.ready);
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) widget.onComplete();
    }
  }

  void _setStep(String label) {
    if (mounted) setState(() => _currentStep = label);
  }

  void _markStep(int index) {
    if (mounted) setState(() => _steps[index] = true);
  }

  Future<void> _loadLocalData() async {
    Future<void> safe(Future<void> Function() fn) async {
      try {
        await fn().timeout(const Duration(seconds: 10));
      } catch (e) {
        debugPrint('[Startup] step failed: $e');
      }
    }

    await safe(() => TelemetryService.instance.init());
    await safe(() => ref.read(settingsProvider.notifier).load());
    await safe(() => ref.read(safetyProvider.notifier).load());
    ref.read(deviceProvider);
    await safe(() => ref.read(localeProvider.notifier).init());
    // Backfill sourceDeviceId on any legacy records missing it
    final deviceId = ref.read(deviceProvider).deviceId;
    await safe(() => SyncMigration.run(deviceId));

    // Load alarm providers
    await safe(() => ref.read(alarmRuleProvider.notifier).load());
    await safe(() => ref.read(notifyChannelProvider.notifier).load());
    await safe(() => ref.read(alarmInstanceProvider.notifier).load());
    await safe(() => ref.read(alarmActionProvider.notifier).load());
    // Load business data
    await safe(() => Future.wait([
          ref.read(voyageProvider.notifier).load(),
          ref.read(taskProvider.notifier).load(),
          ref.read(issueProvider.notifier).load(),
          ref.read(logProvider.notifier).load(),
        ]));

    // Load MOB provider (rules + history)
    await safe(() => ref.read(mobProvider.notifier).load());

    // Start alarm evaluator (watches vessel state and fires alarm instances)
    ref.read(alarmEvaluatorProvider).start();

    // Wire LAN sync callbacks
    final lanSync = ref.read(lanSyncServiceProvider);
    lanSync.onMobAlert = (alert) => ref.read(mobProvider.notifier).receiveMob(alert);
    lanSync.getActiveMob = () => ref.read(mobProvider).activeMob;
    lanSync.getMobRules = () =>
        ref.read(mobProvider).rules.map((r) => r.toJson()).toList();
    lanSync.getAlarmSettings = () => {
          'depthAlarmEnabled': ref.read(safetyProvider).depthAlarmEnabled,
          'depthAlarmThreshold': ref.read(safetyProvider).depthAlarmThreshold,
          'speedAlarmEnabled': ref.read(safetyProvider).speedAlarmEnabled,
          'speedAlarmThreshold': ref.read(safetyProvider).speedAlarmThreshold,
        };
    lanSync.getAlarmRules = () => {
          'rules': ref.read(alarmRuleProvider).map((r) => r.toJson()).toList(),
        };
    lanSync.onAlarmSettingsReceived = (data) =>
        ref.read(safetyProvider.notifier).applyAlarmSync(data);
    lanSync.onAlarmRulesReceived = (records) =>
        ref.read(alarmRuleProvider.notifier).applyRemote(records);
    lanSync.getNotifyChannelCfg = () =>
        ref.read(notifyChannelProvider).toJson();
    lanSync.onNotifyChannelReceived = (data) =>
        ref.read(notifyChannelProvider.notifier).applySync(data);

    // Wire MOB watcher to SignalK raw delta stream
    final mobWatcher = MobWatcherService();
    mobWatcher.updateRules(ref.read(mobProvider).rules);
    mobWatcher.onRuleMatched = (rule) {
      if (!ref.read(mobProvider).isMobActive) {
        ref.read(mobProvider.notifier).trigger(
          triggerSource: 'rule',
          triggerRuleName: rule.name,
        );
      }
    };
    // Keep watcher rules in sync when rules change
    ref.listen(mobProvider.select((s) => s.rules), (_, rules) {
      mobWatcher.updateRules(rules);
    });
    ref.read(signalKClientProvider).onRawDelta = mobWatcher.onDelta;

    // Wire alarm rule / instance / action sync callbacks
    lanSync.onMobRuleSync = (data) =>
        ref.read(mobProvider.notifier).applyRuleRemote(data);
    lanSync.onAlarmRuleSync = (data) =>
        ref.read(alarmRuleProvider.notifier).applyRemote([data]);
    lanSync.onAlarmInstanceSync = (data) =>
        ref.read(alarmInstanceProvider.notifier).upsertRemote(data);
    lanSync.onAlarmActionSync = (data) =>
        ref.read(alarmActionProvider.notifier).applyRemote(data);
  }

  Future<void> _connectSK(AppSettings settings) async {
    String? token;
    if (settings.hasCredentials) {
      try {
        token = await SignalKAuth.login(
          settings.effectiveSignalKUrl,
          settings.signalKUsername,
          settings.signalKPassword,
        );
      } catch (_) {}
    }
    try {
      await ref
          .read(signalKClientProvider)
          .connect(settings.effectiveSignalKUrl, token: token);
      if (mounted) setState(() => _skConnected = true);
    } catch (_) {}
  }

  // ── Wizard actions ─────────────────────────────────────────────────────────

  void _goToPage(int page) {
    setState(() => _wizardPage = page);
    _pageCtrl.animateToPage(
      page,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  /// Called from page 0 (Welcome).
  void _wizardNext() => _goToPage(1);

  /// Called from page 1 (Device Name).
  Future<void> _wizardSaveDeviceName() async {
    final name = _deviceNameCtrl.text.trim();
    if (name.isEmpty) return;

    // Save device name
    await ref.read(settingsProvider.notifier).update(
          ref.read(settingsProvider).copyWith(deviceName: name),
        );

    if (!mounted) return;

    if (_peersFound > 0) {
      // LAN already found — auto-join, no further config needed.
      widget.onComplete();
    } else {
      // No LAN peers — guide through vessel name + SK setup.
      _goToPage(2);
    }
  }

  /// Called from page 2 (Vessel Name).
  void _wizardNextVessel() {
    if (_vesselNameCtrl.text.trim().isNotEmpty) _goToPage(3);
  }

  /// Called from page 3 (Signal K). Saves vessel name + SK then finishes.
  Future<void> _wizardFinish() async {
    final vesselName = _vesselNameCtrl.text.trim();
    if (vesselName.isEmpty) return;

    setState(() {
      _wizardConnecting = true;
      _wizardError = null;
    });

    // Save vessel name
    await ref.read(settingsProvider.notifier).update(
          ref.read(settingsProvider).copyWith(vesselName: vesselName),
        );

    // Connect SK if configured in wizard
    final host = _skHostCtrl.text.trim();
    if (host.isNotEmpty) {
      final port = int.tryParse(_skPortCtrl.text.trim()) ?? 3000;
      await ref.read(settingsProvider.notifier).update(
            ref.read(settingsProvider).copyWith(
                  signalKHost: host,
                  signalKPort: port,
                  signalKUsername: _skUserCtrl.text.trim(),
                  signalKPassword: _skPassCtrl.text,
                ),
          );
      try {
        await _connectSK(ref.read(settingsProvider));
      } catch (_) {
        if (mounted) {
          setState(() {
            _wizardConnecting = false;
            _wizardError = '连接失败，请检查地址';
          });
        }
        return;
      }
    }

    if (mounted) {
      setState(() => _wizardConnecting = false);
      widget.onComplete();
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          child: switch (_phase) {
            _Phase.loading || _Phase.ready => _buildLoading(),
            _Phase.wizard => _buildWizard(),
          },
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return Center(
      key: const ValueKey('loading'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Logo / title
            const Icon(Icons.sailing_rounded,
                size: 72, color: AppColors.cyan),
            const SizedBox(height: 16),
            const Text(
              'Yokuli',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 32,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '智能船舶管理',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  letterSpacing: 2),
            ),
            const SizedBox(height: 48),

            // Progress steps
            _StepRow(
              done: _steps[0],
              label: '加载本地数据',
              pulse: !_steps[0],
              pulseCtrl: _pulseCtrl,
            ),
            const SizedBox(height: 12),
            _StepRow(
              done: _steps[1],
              label: '启动局域网同步',
              pulse: _steps[0] && !_steps[1],
              pulseCtrl: _pulseCtrl,
            ),
            const SizedBox(height: 12),
            _StepRow(
              done: _steps[2],
              label: _peersFound > 0
                  ? '搜索设备 — 发现 $_peersFound 台'
                  : '搜索设备中…',
              pulse: _steps[1] && !_steps[2],
              pulseCtrl: _pulseCtrl,
            ),
            const SizedBox(height: 12),
            _StepRow(
              done: _steps[3],
              label: _skConnected ? 'Signal K 已连接' : '连接 Signal K',
              pulse: _steps[2] && !_steps[3],
              pulseCtrl: _pulseCtrl,
            ),

            const SizedBox(height: 32),
            AnimatedOpacity(
              opacity: _phase == _Phase.ready ? 1.0 : 0.6,
              duration: const Duration(milliseconds: 300),
              child: Text(
                _currentStep,
                style: const TextStyle(
                    color: AppColors.textMuted, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWizard() {
    // When peers are found: Welcome(0) + DeviceName(1) = 2 dots total.
    // When no peers: Welcome(0) + DeviceName(1) + VesselName(2) + SK(3) = 4 dots.
    final totalDots = _peersFound > 0 ? 2 : 4;
    return Column(
      key: const ValueKey('wizard'),
      children: [
        // Progress dots
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(totalDots, (i) {
              final active = i == _wizardPage;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: active ? 24 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: active ? AppColors.cyan : AppColors.border,
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),
        ),

        Expanded(
          child: PageView(
            controller: _pageCtrl,
            physics: const NeverScrollableScrollPhysics(),
            onPageChanged: (i) => setState(() => _wizardPage = i),
            children: [
              // Page 0: Welcome
              _WizardPageWelcome(onNext: _wizardNext),
              // Page 1: Device Name
              _WizardPageDeviceName(
                controller: _deviceNameCtrl,
                peersFound: _peersFound,
                onSave: _wizardSaveDeviceName,
              ),
              // Page 2: Vessel Name (only reached if no peers)
              _WizardPageVessel(
                controller: _vesselNameCtrl,
                onNext: _wizardNextVessel,
              ),
              // Page 3: Signal K (only reached if no peers)
              _WizardPageSignalK(
                hostCtrl: _skHostCtrl,
                portCtrl: _skPortCtrl,
                userCtrl: _skUserCtrl,
                passCtrl: _skPassCtrl,
                connecting: _wizardConnecting,
                error: _wizardError,
                onFinish: _wizardFinish,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Step row widget
// ---------------------------------------------------------------------------

class _StepRow extends StatelessWidget {
  final bool done;
  final String label;
  final bool pulse;
  final AnimationController pulseCtrl;

  const _StepRow({
    required this.done,
    required this.label,
    required this.pulse,
    required this.pulseCtrl,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: done
              ? const Icon(Icons.check_circle_rounded,
                  color: AppColors.cyan, size: 20)
              : pulse
                  ? AnimatedBuilder(
                      animation: pulseCtrl,
                      builder: (_, __) => Opacity(
                        opacity: 0.4 + 0.6 * pulseCtrl.value,
                        child: const Icon(
                          Icons.radio_button_unchecked_rounded,
                          color: AppColors.textMuted,
                          size: 20,
                        ),
                      ),
                    )
                  : const Icon(Icons.radio_button_unchecked_rounded,
                      color: AppColors.inactive, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: done ? AppColors.textPrimary : AppColors.textSecondary,
              fontSize: 14,
              fontWeight: done ? FontWeight.w500 : FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Wizard pages
// ---------------------------------------------------------------------------

class _WizardPageWelcome extends StatelessWidget {
  final VoidCallback onNext;
  const _WizardPageWelcome({required this.onNext});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.sailing_rounded, size: 80, color: AppColors.cyan),
          const SizedBox(height: 24),
          const Text(
            '欢迎使用 Yokuli',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 26,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '只需几步配置，即可开始您的智能航行体验',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 48),
          ElevatedButton(
            onPressed: onNext,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: AppColors.cyan,
              foregroundColor: AppColors.background,
            ),
            child: const Text('开始配置',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _WizardPageDeviceName extends StatelessWidget {
  final TextEditingController controller;
  final int peersFound;
  final VoidCallback onSave;

  const _WizardPageDeviceName({
    required this.controller,
    required this.peersFound,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.smartphone_rounded,
              size: 48, color: AppColors.cyan),
          const SizedBox(height: 20),
          const Text(
            '给这台设备起个名字',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            peersFound > 0
                ? '发现 $peersFound 台设备在同一网络。\n输入名称后将自动加入。'
                : '名称将显示在局域网其他设备上，便于识别',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 32),
          TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(
                color: AppColors.textPrimary, fontSize: 18),
            decoration: const InputDecoration(
              hintText: '例如：舵手平板',
              hintStyle: TextStyle(color: AppColors.textMuted),
              prefixIcon: Icon(Icons.badge_rounded,
                  color: AppColors.textMuted),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onSave(),
          ),
          const SizedBox(height: 40),
          ElevatedButton(
            onPressed: onSave,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: AppColors.cyan,
              foregroundColor: AppColors.background,
            ),
            child: Text(
              peersFound > 0 ? '加入局域网' : '继续',
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _WizardPageVessel extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onNext;
  const _WizardPageVessel(
      {required this.controller, required this.onNext});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '给您的船起个名字',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '这个名称会显示在所有设备上',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 32),
          TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(
                color: AppColors.textPrimary, fontSize: 18),
            decoration: const InputDecoration(
              hintText: '例如：追风号',
              hintStyle: TextStyle(color: AppColors.textMuted),
              prefixIcon: Icon(Icons.directions_boat_rounded,
                  color: AppColors.textMuted),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onNext(),
          ),
          const SizedBox(height: 40),
          ElevatedButton(
            onPressed: onNext,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: AppColors.cyan,
              foregroundColor: AppColors.background,
            ),
            child: const Text('继续',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _WizardPageSignalK extends StatelessWidget {
  final TextEditingController hostCtrl;
  final TextEditingController portCtrl;
  final TextEditingController userCtrl;
  final TextEditingController passCtrl;
  final bool connecting;
  final String? error;
  final VoidCallback onFinish;
  const _WizardPageSignalK({
    required this.hostCtrl,
    required this.portCtrl,
    required this.userCtrl,
    required this.passCtrl,
    required this.connecting,
    this.error,
    required this.onFinish,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '配置 Signal K 服务器',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '可选 — 连接您的船载 Signal K 服务器获取实时数据',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 32),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: hostCtrl,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: const InputDecoration(
                    labelText: '主机 / 地址',
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
                width: 90,
                child: TextField(
                  controller: portCtrl,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: const InputDecoration(labelText: '端口'),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: userCtrl,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: const InputDecoration(
              labelText: '用户名（可选）',
              prefixIcon: Icon(Icons.person_rounded),
            ),
            autocorrect: false,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: passCtrl,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: const InputDecoration(
              labelText: '密码（可选）',
              prefixIcon: Icon(Icons.lock_rounded),
            ),
            obscureText: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onFinish(),
          ),
          if (error != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.error_outline_rounded,
                    size: 14, color: AppColors.danger),
                const SizedBox(width: 6),
                Text(error!,
                    style: const TextStyle(
                        color: AppColors.danger, fontSize: 12)),
              ],
            ),
          ],
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: connecting ? null : onFinish,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: AppColors.cyan,
              foregroundColor: AppColors.background,
            ),
            child: connecting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: AppColors.background),
                  )
                : const Text('完成配置',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 16),
          Center(
            child: TextButton(
              onPressed: connecting ? null : onFinish,
              child: const Text(
                '稍后配置',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
