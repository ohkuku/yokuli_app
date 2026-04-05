import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:latlong2/latlong.dart' hide Path;

import '../../../core/models/weather_state.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/weather_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../home/widgets/weather_background.dart';
import '../widgets/wind_map_layer.dart';

// ---------------------------------------------------------------------------
// WeatherScreen — 5-tab professional maritime weather
// ---------------------------------------------------------------------------

class WeatherScreen extends ConsumerStatefulWidget {
  const WeatherScreen({super.key});

  @override
  ConsumerState<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends ConsumerState<WeatherScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(weatherProvider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final weather = ref.watch(weatherProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.25),
        elevation: 0,
        leading: const BackButton(color: Colors.white),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '海况预报',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
            ),
            if (weather.locationLabel != null)
              Text(
                weather.locationLabel!,
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
          ],
        ),
        actions: [
          if (weather.isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
              ),
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
              onPressed: () => ref.read(weatherProvider.notifier).refresh(),
            ),
            // DEV: long-press to probe all variable names → logcat
            IconButton(
              icon: const Icon(Icons.science_outlined, color: Colors.white30, size: 18),
              tooltip: 'Probe MetOcean vars',
              onPressed: () {
                final key = ref.read(settingsProvider).metServiceApiKey;
                WeatherNotifier.probeVariables(key);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Probing variables → check logcat')),
                );
              },
            ),
          ],
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.cyanAccent,
          indicatorWeight: 2,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontSize: 13),
          tabs: const [
            Tab(text: '概览'),
            Tab(text: '风'),
            Tab(text: '浪'),
            Tab(text: '潮汐'),
            Tab(text: '预报'),
          ],
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const WeatherBackground(),
          SafeArea(
            child: Column(
              children: [
                // Error banner
                if (weather.error != null)
                  _ErrorBanner(error: weather.error!),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _OverviewTab(weather: weather),
                      _WindTab(weather: weather),
                      _WavesTab(hourly: weather.hourly),
                      _TidesTab(tides: weather.tides),
                      _ForecastTab(daily: weather.daily),
                    ],
                  ),
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
// Error banner
// ---------------------------------------------------------------------------

class _ErrorBanner extends StatelessWidget {
  final String error;
  const _ErrorBanner({required this.error});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          color: AppColors.danger.withOpacity(0.18),
          child: Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.white70, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  error,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Glass card helper
// ---------------------------------------------------------------------------

Widget _glassCard({required Widget child, EdgeInsets? padding, double radius = 16}) {
  return ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.10),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: Colors.white.withOpacity(0.16)),
        ),
        padding: padding ?? const EdgeInsets.all(16),
        child: child,
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// TAB 1 — 概览 (Overview)
// ---------------------------------------------------------------------------

class _OverviewTab extends StatelessWidget {
  final WeatherState weather;
  const _OverviewTab({required this.weather});

  static int _beaufortForce(double kn) {
    if (kn < 1)  return 0;
    if (kn < 4)  return 1;
    if (kn < 7)  return 2;
    if (kn < 11) return 3;
    if (kn < 17) return 4;
    if (kn < 22) return 5;
    if (kn < 28) return 6;
    if (kn < 34) return 7;
    if (kn < 41) return 8;
    if (kn < 48) return 9;
    if (kn < 56) return 10;
    if (kn < 64) return 11;
    return 12;
  }

  Color _riskColor(double? windKn) {
    if (windKn == null) return AppColors.success;
    if (windKn >= 34) return AppColors.danger;
    if (windKn >= 22) return const Color(0xFFFF9F0A); // amber
    return AppColors.success;
  }

  String _riskText(double? windKn) {
    if (windKn == null) return '海况良好';
    final bf = _beaufortForce(windKn);
    if (windKn >= 34) return '警告：强风浪 — 蒲福 $bf 级';
    if (windKn >= 22) return '注意：风力较强 — 蒲福 $bf 级';
    return '海况良好 — 蒲福 $bf 级';
  }

  @override
  Widget build(BuildContext context) {
    final windKn = weather.windSpeed;
    final riskColor = _riskColor(windKn);
    final riskText = _riskText(windKn);
    final windDir = weather.windDirection;
    final windLabel = windDir != null ? windDirectionLabel(windDir) : '--';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Risk assessment banner — only when we have data
          if (weather.windSpeed != null || weather.waveHeight != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: riskColor.withOpacity(0.20),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: riskColor.withOpacity(0.45)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        windKn != null && windKn >= 34
                            ? Icons.warning_rounded
                            : windKn != null && windKn >= 22
                                ? Icons.info_rounded
                                : Icons.check_circle_rounded,
                        color: riskColor,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        riskText,
                        style: TextStyle(
                          color: riskColor,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (windKn != null) ...[
                        const Spacer(),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${windKn.toStringAsFixed(0)} kn',
                              style: TextStyle(color: riskColor.withOpacity(0.9), fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                            Text(
                              'B${_beaufortForce(windKn)}',
                              style: TextStyle(color: riskColor.withOpacity(0.65), fontSize: 11),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],

          // Fetch time
          if (weather.fetchedAt != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                '更新 ${DateFormat('HH:mm').format(weather.fetchedAt!.toLocal())}',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
                textAlign: TextAlign.right,
              ),
            ),

          // Loading
          if (weather.isLoading && weather.windSpeed == null)
            _glassCard(
              padding: const EdgeInsets.all(48),
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2),
              ),
            )
          else
            // Conditions grid — 2 columns
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.55,
              children: [
                _ConditionCell(
                  icon: Icons.air_rounded,
                  label: '风速',
                  value: weather.windSpeed != null
                      ? '${weather.windSpeed!.toStringAsFixed(1)} kn'
                      : '--',
                  sub: windDir != null
                      ? '$windLabel · ${windDir}°${weather.windGust != null ? '  阵 ${weather.windGust!.toStringAsFixed(0)}kn' : ''}'
                      : null,
                ),
                _ConditionCell(
                  icon: Icons.waves_rounded,
                  label: '浪高',
                  value: weather.waveHeight != null
                      ? '${weather.waveHeight!.toStringAsFixed(1)} m'
                      : '--',
                  sub: weather.wavePeriod != null
                      ? '周期 ${weather.wavePeriod!.toStringAsFixed(0)}s'
                      : null,
                ),
                _ConditionCell(
                  icon: Icons.thermostat_rounded,
                  label: '气温',
                  value: weather.temperature != null
                      ? '${weather.temperature!.round()}°C'
                      : '--',
                  sub: weather.dewPoint != null
                      ? '露点 ${weather.dewPoint!.round()}°C'
                      : null,
                ),
                _ConditionCell(
                  icon: Icons.speed_rounded,
                  label: '气压',
                  value: weather.pressure != null
                      ? '${weather.pressure!.round()} hPa'
                      : '--',
                  sub: _pressureTrendLabel(weather.pressureTrend),
                  subColor: (weather.pressureTrend != null && weather.pressureTrend! <= -6.0)
                      ? AppColors.danger
                      : null,
                ),
                _ConditionCell(
                  icon: Icons.cloud_outlined,
                  label: '云量',
                  value: weather.cloudCover != null
                      ? '${(weather.cloudCover! * 100).round()}%'
                      : '--',
                  sub: weather.precipitation != null && weather.precipitation! > 0
                      ? '降水 ${weather.precipitation!.toStringAsFixed(1)} mm/h'
                      : null,
                ),
                _ConditionCell(
                  icon: Icons.water_drop_rounded,
                  label: '湿度',
                  value: weather.humidity != null
                      ? '${weather.humidity!.round()}%'
                      : '--',
                  sub: weather.dewPoint != null
                      ? '露点 ${weather.dewPoint!.round()}°C'
                      : null,
                ),
              ],
            ),

          // Description
          if (weather.description != null) ...[
            const SizedBox(height: 14),
            _glassCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    iconForCode(weather.weatherCode ?? 0),
                    color: Colors.white70,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    weather.description!,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ConditionCell extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? sub;
  final Color? subColor;

  const _ConditionCell({
    required this.icon,
    required this.label,
    required this.value,
    this.sub,
    this.subColor,
  });

  @override
  Widget build(BuildContext context) {
    return _glassCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: Colors.white54),
              const SizedBox(width: 5),
              Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
            ],
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w500,
              height: 1.1,
            ),
          ),
          if (sub != null)
            Text(
              sub!,
              style: TextStyle(
                color: subColor ?? Colors.white.withOpacity(0.5),
                fontSize: 10,
              ),
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// TAB 2 — 风 (Wind)
// ---------------------------------------------------------------------------

class _WindTab extends StatelessWidget {
  final WeatherState weather;
  const _WindTab({required this.weather});

  @override
  Widget build(BuildContext context) {
    final data = weather.hourly.take(24).toList();

    if (weather.windSpeed == null && data.isEmpty && weather.windGrid.isEmpty) {
      return _EmptyPlaceholder(message: '暂无风速数据');
    }

    // Grid available → full-screen map with bottom info sheet
    if (weather.windGrid.isNotEmpty) {
      return _WindMapView(weather: weather, hourly: data);
    }

    // No grid yet → single-point particle canvas while grid loads
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _WindFlowCard(
            windSpeed: weather.windSpeed ?? 0,
            windDir: weather.windDirection ?? 0,
            windGust: weather.windGust,
            hourly: data,
          ),
          const SizedBox(height: 14),

          // 24h wind bar chart
          if (data.isNotEmpty)
            _glassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '未来24小时风速 (kn)',
                    style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(height: 160, child: _WindBarChart(data: data)),
                ],
              ),
            ),

          const SizedBox(height: 14),

          // 24h pressure sparkline
          if (data.any((h) => h.pressure != null))
            _glassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        '气压趋势 (hPa)',
                        style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      if (weather.pressureTrend != null) ...[
                        const Spacer(),
                        Text(
                          _pressureTrendLabel(weather.pressureTrend) ?? '',
                          style: TextStyle(
                            color: weather.pressureTrend! <= -6.0
                                ? AppColors.danger
                                : Colors.white54,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(height: 100, child: _PressureSparkline(hourly: data)),
                ],
              ),
            ),

          const SizedBox(height: 14),
          // Beaufort legend
          _glassCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '蒲福风力等级',
                  style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    _BeaufortChip(color: const Color(0xFF30D158), label: '0-3级 轻风'),
                    _BeaufortChip(color: const Color(0xFFFFD60A), label: '4-5级 中风'),
                    _BeaufortChip(color: const Color(0xFFFF9F0A), label: '6-7级 强风'),
                    _BeaufortChip(color: const Color(0xFFFF453A), label: '8+级 暴风'),
                  ],
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
// ---------------------------------------------------------------------------
// Wind map view — full-screen Windy-style map with layers + timeline + route
// ---------------------------------------------------------------------------

class _WindMapView extends ConsumerStatefulWidget {
  final WeatherState weather;
  final List<HourlyForecast> hourly;
  const _WindMapView({required this.weather, required this.hourly});

  @override
  ConsumerState<_WindMapView> createState() => _WindMapViewState();
}

class _WindMapViewState extends ConsumerState<_WindMapView>
    with SingleTickerProviderStateMixin {
  // ── Display state ──────────────────────────────────────────────────────────
  bool _panelOpen  = false;
  WindLayer     _layer    = WindLayer.wind;
  ForecastModel _model    = ForecastModel.gfs;
  int           _timeStep = 0; // index 0..5 into forecastTimeline

  // Key to call refreshCurrentViewport() on the map widget
  final _mapKey = GlobalKey<WindMapWidgetState>();

  // ── Playback ───────────────────────────────────────────────────────────────
  bool   _playing = false;
  Timer? _playTimer;

  // ── Route planning ─────────────────────────────────────────────────────────
  bool            _routeMode   = false;
  final List<LatLng> _routePoints = [];

  // ── Timeline load state ────────────────────────────────────────────────────
  bool _timelineLoading = false;

  @override
  void initState() {
    super.initState();
    // Timeline loads on-demand when user presses the play button
  }

  @override
  void dispose() {
    _playTimer?.cancel();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _onGridNeeded(double lat, double lon, double step, int n) {
    // Only fetch data for the active layer — never fire two requests at once
    if (_layer == WindLayer.waves) {
      ref.read(weatherProvider.notifier).refetchWaveGrid(
        lat: lat, lon: lon, step: step, n: n,
      );
    } else {
      // wind / pressure / rain all use the wind grid
      ref.read(weatherProvider.notifier).refetchWindGrid(
        lat: lat, lon: lon, step: step, n: n,
      );
    }
  }

  void _maybeLoadTimeline() {
    if (_timelineLoading) return;
    final w = widget.weather;
    if (w.windGrid.isEmpty || w.forecastTimeline.isNotEmpty) return;
    final lat = _centerLat(w);
    final lon = _centerLon(w);
    if (lat == null || lon == null) return;
    setState(() => _timelineLoading = true);
    ref.read(weatherProvider.notifier).fetchForecastTimeline(
      lat: lat, lon: lon,
    ).then((_) {
      if (mounted) setState(() => _timelineLoading = false);
    }).catchError((_) {
      if (mounted) setState(() => _timelineLoading = false);
    });
  }

  void _togglePlay() {
    if (_playing) {
      _playTimer?.cancel();
      setState(() => _playing = false);
      return;
    }
    setState(() => _playing = true);
    _playTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) { _playTimer?.cancel(); return; }
      final maxStep = math.max(0,
          widget.weather.forecastTimeline.length - 1);
      setState(() {
        _timeStep = (_timeStep + 1) % (maxStep + 1);
        if (_timeStep == 0) {
          _playing = false;
          _playTimer?.cancel();
        }
      });
    });
  }

  static double? _centerLat(WeatherState w) => w.windGrid.isNotEmpty
      ? w.windGrid.map((p) => p.lat).reduce((a, b) => a + b) / w.windGrid.length
      : null;

  static double? _centerLon(WeatherState w) => w.windGrid.isNotEmpty
      ? w.windGrid.map((p) => p.lon).reduce((a, b) => a + b) / w.windGrid.length
      : null;

  void _onMapTap(LatLng latLng) {
    if (_routeMode) {
      setState(() => _routePoints.add(latLng));
      return;
    }
    // Tap-to-forecast
    _showPointForecast(latLng);
  }

  void _showPointForecast(LatLng latLng) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _TapForecastSheet(
        lat: latLng.latitude,
        lon: latLng.longitude,
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  static const _timeLabels = ['现在', '+3h', '+6h', '+12h', '+24h', '+48h'];

  @override
  Widget build(BuildContext context) {
    final w   = widget.weather;
    final lat = _centerLat(w);
    final lon = _centerLon(w);

    return Stack(
      children: [
        // ── Full-screen map ────────────────────────────────────────────────
        Positioned.fill(
          child: WindMapWidget(
            key: _mapKey,
            windGrid: w.windGrid,
            waveGrid: w.waveGrid,
            forecastTimeline: w.forecastTimeline,
            activeLayer: _layer,
            model: _model,
            timeStepIndex: _timeStep,
            centerLat: lat ?? 0,
            centerLon: lon ?? 0,
            vesselLat: lat,
            vesselLon: lon,
            onGridNeeded: _onGridNeeded,
            onMapTap: _onMapTap,
          ),
        ),

        // ── Route waypoint count overlay ───────────────────────────────────
        if (_routeMode)
          Positioned(
            top: 80, left: 0, right: 0,
            child: IgnorePointer(
              child: Center(child: _RouteOverlay(points: _routePoints)),
            ),
          ),

        // ── Top-left: conditions pill + layer legend ──────────────────────
        Positioned(
          top: 12,
          left: 12,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _WindInfoPill(weather: w),
              if (_layer != WindLayer.wind) ...[
                const SizedBox(height: 8),
                if (_layer == WindLayer.waves) const MapLayerLegend.wave(),
                if (_layer == WindLayer.rain)  const MapLayerLegend.rain(),
                if (_layer == WindLayer.pressure) const MapLayerLegend.pressure(),
              ],
            ],
          ),
        ),

        // ── Top-right: model chip + route button ───────────────────────────
        Positioned(
          top: 12,
          right: 12,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _glassChip(
                onTap: _showModelPicker,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_download_outlined,
                        size: 12, color: Colors.white70),
                    const SizedBox(width: 4),
                    Text(_modelLabel(_model),
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12,
                            fontWeight: FontWeight.w600)),
                    const Icon(Icons.expand_more_rounded,
                        size: 14, color: Colors.white54),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // Manual data refresh button
              _glassChip(
                onTap: () => _mapKey.currentState?.refreshCurrentViewport(),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh_rounded, size: 12, color: Colors.white70),
                    SizedBox(width: 4),
                    Text('刷新数据',
                        style: TextStyle(
                            color: Colors.white, fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _glassChip(
                active: _routeMode,
                onTap: () {
                  setState(() {
                    _routeMode = !_routeMode;
                    if (!_routeMode) _routePoints.clear();
                  });
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.route_rounded,
                        size: 12,
                        color: _routeMode ? AppColors.cyan : Colors.white70),
                    const SizedBox(width: 4),
                    Text(_routeMode ? '清除路线' : '规划路线',
                        style: TextStyle(
                            color: _routeMode ? AppColors.cyan : Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ── Right side: layer selector ────────────────────────────────────
        Positioned(
          right: 12,
          top: 0,
          bottom: 0,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _LayerButton(
                  icon: Icons.air_rounded,
                  label: '风',
                  active: _layer == WindLayer.wind,
                  onTap: () => setState(() => _layer = WindLayer.wind),
                ),
                const SizedBox(height: 8),
                _LayerButton(
                  icon: Icons.waves_rounded,
                  label: '浪',
                  active: _layer == WindLayer.waves,
                  onTap: () {
                    setState(() => _layer = WindLayer.waves);
                    if (w.waveGrid.isEmpty && lat != null) {
                      ref.read(weatherProvider.notifier).refetchWaveGrid(
                        lat: lat, lon: lon!,
                      );
                    }
                  },
                ),
                const SizedBox(height: 8),
                _LayerButton(
                  icon: Icons.speed_rounded,
                  label: '气压',
                  active: _layer == WindLayer.pressure,
                  onTap: () => setState(() => _layer = WindLayer.pressure),
                ),
                const SizedBox(height: 8),
                _LayerButton(
                  icon: Icons.water_drop_rounded,
                  label: '降雨',
                  active: _layer == WindLayer.rain,
                  onTap: () => setState(() => _layer = WindLayer.rain),
                ),
              ],
            ),
          ),
        ),

        // ── Bottom: timeline + info panel ─────────────────────────────────
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Timeline strip
              _buildTimeline(w),
              // Info panel
              _buildInfoPanel(w),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTimeline(WeatherState w) {
    final hasTimeline = w.forecastTimeline.isNotEmpty;
    final maxStep = hasTimeline ? w.forecastTimeline.length - 1 : 5;

    return Container(
      color: Colors.black.withOpacity(0.55),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          // Play / pause
          GestureDetector(
            onTap: hasTimeline ? _togglePlay : _maybeLoadTimeline,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _playing ? AppColors.cyan.withOpacity(0.25) : Colors.white12,
                border: Border.all(
                  color: _playing ? AppColors.cyan : Colors.white24,
                ),
              ),
              child: _timelineLoading
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: Colors.white54))
                  : Icon(
                      _playing
                          ? Icons.pause_rounded
                          : (hasTimeline ? Icons.play_arrow_rounded : Icons.download_rounded),
                      color: _playing ? AppColors.cyan : Colors.white70,
                      size: 18,
                    ),
            ),
          ),
          const SizedBox(width: 8),
          // Step labels
          Expanded(
            child: Row(
              children: List.generate(
                _timeLabels.length,
                (i) {
                  final active = i == _timeStep;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _timeStep = i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        decoration: BoxDecoration(
                          color: active
                              ? AppColors.cyan.withOpacity(0.20)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          border: active
                              ? Border.all(color: AppColors.cyan.withOpacity(0.5))
                              : null,
                        ),
                        child: Text(
                          _timeLabels[i],
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: active ? AppColors.cyan : Colors.white38,
                            fontSize: 10,
                            fontWeight: active
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoPanel(WeatherState w) {
    return GestureDetector(
      onTap: () => setState(() => _panelOpen = !_panelOpen),
      onVerticalDragEnd: (d) {
        if (d.primaryVelocity != null) {
          setState(() => _panelOpen = d.primaryVelocity! < 0);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        height: _panelOpen ? 260 : 48,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.78),
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(16)),
          border: Border(
              top: BorderSide(color: Colors.white.withOpacity(0.12))),
        ),
        child: Column(
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.30),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            if (_panelOpen) ...[
              if (widget.hourly.any((h) => h.pressure != null)) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  child: Row(children: [
                    const Text('气压趋势',
                        style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                    if (w.pressureTrend != null) ...[
                      const Spacer(),
                      Text(
                        _pressureTrendLabel(w.pressureTrend) ?? '',
                        style: TextStyle(
                          color: (w.pressureTrend ?? 0) <= -6.0
                              ? AppColors.danger
                              : Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ]),
                ),
                SizedBox(
                  height: 80,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                    child: _PressureSparkline(hourly: widget.hourly),
                  ),
                ),
              ],
              if (widget.hourly.isNotEmpty) ...[
                const Divider(color: Colors.white12, height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(children: [
                    const Text('未来24h风速 (kn)',
                        style: TextStyle(
                            color: Colors.white54, fontSize: 11)),
                    const Spacer(),
                    // Model selector inline
                    GestureDetector(
                      onTap: _showModelPicker,
                      child: Text(
                        '数据: ${_modelLabel(_model)}',
                        style: const TextStyle(
                            color: Colors.white30, fontSize: 10),
                      ),
                    ),
                  ]),
                ),
                SizedBox(
                  height: 80,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                    child: _WindBarChart(
                        data: widget.hourly.take(24).toList()),
                  ),
                ),
              ],
            ] else
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _WindQuickStats(weather: w),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showModelPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1F2E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('预报模型',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            for (final m in ForecastModel.values)
              ListTile(
                leading: Icon(
                  m == _model
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  color: m == _model ? AppColors.cyan : Colors.white38,
                ),
                title: Text(_modelLabel(m),
                    style: const TextStyle(color: Colors.white)),
                subtitle: Text(_modelDesc(m),
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 11)),
                onTap: () {
                  Navigator.pop(context);
                  setState(() => _model = m);
                  // Trigger refetch with new model (future: pass model param)
                  final w = widget.weather;
                  final lat = _centerLat(w);
                  final lon = _centerLon(w);
                  if (lat != null) {
                    ref.read(weatherProvider.notifier).refetchWindGrid(
                      lat: lat, lon: lon!,
                    );
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  static String _modelLabel(ForecastModel m) => switch (m) {
    ForecastModel.gfs   => 'GFS',
    ForecastModel.ecmwf => 'ECMWF',
    ForecastModel.icon  => 'ICON',
  };

  static String _modelDesc(ForecastModel m) => switch (m) {
    ForecastModel.gfs   => 'NOAA全球预报，6h分辨率',
    ForecastModel.ecmwf => '欧洲中期天气预报，精度更高',
    ForecastModel.icon  => 'DWD德国天气局，高分辨率',
  };

  Widget _glassChip({
    required Widget child,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: active
                  ? AppColors.cyan.withOpacity(0.20)
                  : Colors.black.withOpacity(0.50),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: active
                    ? AppColors.cyan.withOpacity(0.60)
                    : Colors.white.withOpacity(0.14),
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

// ── Layer selector button ──────────────────────────────────────────────────

class _LayerButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _LayerButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active
              ? AppColors.cyan.withOpacity(0.25)
              : Colors.black.withOpacity(0.55),
          border: Border.all(
            color: active
                ? AppColors.cyan.withOpacity(0.80)
                : Colors.white.withOpacity(0.18),
            width: active ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 16,
                color: active ? AppColors.cyan : Colors.white54),
            Text(label,
                style: TextStyle(
                    color: active ? AppColors.cyan : Colors.white38,
                    fontSize: 8,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ── Route overlay (drawn outside the FlutterMap) ──────────────────────────

class _RouteOverlay extends StatelessWidget {
  final List<LatLng> points;
  const _RouteOverlay({required this.points});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.70),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.cyan.withOpacity(0.5)),
        ),
        child: Text(
          '${points.length} 个航点  点击地图继续添加',
          style: const TextStyle(
              color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

// ── Tap-to-forecast bottom sheet ──────────────────────────────────────────

class _TapForecastSheet extends ConsumerStatefulWidget {
  final double lat, lon;
  const _TapForecastSheet({required this.lat, required this.lon});

  @override
  ConsumerState<_TapForecastSheet> createState() => _TapForecastSheetState();
}

class _TapForecastSheetState extends ConsumerState<_TapForecastSheet> {
  List<HourlyForecast>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ref
          .read(weatherProvider.notifier)
          .fetchPointForecast(lat: widget.lat, lon: widget.lon);
      if (mounted) setState(() { _data = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final lat = widget.lat.toStringAsFixed(3);
    final lon = widget.lon.toStringAsFixed(3);

    return Container(
      height: MediaQuery.of(context).size.height * 0.55,
      decoration: const BoxDecoration(
        color: Color(0xFF0E1524),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                const Icon(Icons.place_rounded,
                    color: AppColors.cyan, size: 16),
                const SizedBox(width: 6),
                Text('$lat, $lon',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
                const Spacer(),
                const Text('48h预报',
                    style: TextStyle(
                        color: Colors.white38, fontSize: 12)),
              ],
            ),
          ),
          const Divider(color: Colors.white12, height: 1),
          if (_loading)
            const Expanded(
              child: Center(
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.cyan),
              ),
            )
          else if (_error != null || _data == null || _data!.isEmpty)
            const Expanded(
              child: Center(
                child: Text('无法获取预报数据',
                    style: TextStyle(color: Colors.white38)),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: math.min(48, _data!.length),
                separatorBuilder: (_, __) =>
                    const Divider(color: Colors.white10, height: 1),
                itemBuilder: (_, i) {
                  final h = _data![i];
                  final time = '${h.time.hour.toString().padLeft(2, '0')}:00';
                  final date = '${h.time.month}/${h.time.day}';
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 50,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(time,
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 12)),
                              Text(date,
                                  style: const TextStyle(
                                      color: Colors.white30, fontSize: 10)),
                            ],
                          ),
                        ),
                        if (h.windSpeed != null) ...[
                          Icon(Icons.air_rounded,
                              size: 14,
                              color: _beaufortColor(h.windSpeed!)),
                          const SizedBox(width: 4),
                          SizedBox(
                            width: 60,
                            child: Text(
                              '${h.windSpeed!.toStringAsFixed(0)} kn '
                              '${h.windDir != null ? windDirectionLabel(h.windDir!) : ""}',
                              style: TextStyle(
                                  color: _beaufortColor(h.windSpeed!),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                        if (h.waveHeight != null) ...[
                          const Icon(Icons.waves_rounded,
                              size: 14, color: Colors.lightBlueAccent),
                          const SizedBox(width: 4),
                          SizedBox(
                            width: 48,
                            child: Text(
                              '${h.waveHeight!.toStringAsFixed(1)} m',
                              style: const TextStyle(
                                  color: Colors.lightBlueAccent,
                                  fontSize: 12),
                            ),
                          ),
                        ],
                        const Spacer(),
                        if (h.pressure != null)
                          Text(
                            '${h.pressure!.round()} hPa',
                            style: const TextStyle(
                                color: Colors.white30, fontSize: 11),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _WindInfoPill extends StatelessWidget {
  final WeatherState weather;
  const _WindInfoPill({required this.weather});

  @override
  Widget build(BuildContext context) {
    final ws = weather.windSpeed;
    final dir = weather.windDirection;
    final force = ws != null ? _OverviewTab._beaufortForce(ws) : null;
    final color = ws != null ? _beaufortColor(ws) : Colors.white54;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.45),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.air_rounded, color: color, size: 16),
              const SizedBox(width: 6),
              Text(
                ws != null
                    ? '${ws.toStringAsFixed(0)} kn  B${force!}'
                    : '--',
                style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700),
              ),
              if (dir != null) ...[
                const SizedBox(width: 6),
                Text(
                  'FROM ${windDirectionLabel(dir)}',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _WindQuickStats extends StatelessWidget {
  final WeatherState weather;
  const _WindQuickStats({required this.weather});

  @override
  Widget build(BuildContext context) {
    final items = <({String label, String value, Color color})>[
      if (weather.windSpeed != null)
        (label: '风速', value: '${weather.windSpeed!.toStringAsFixed(1)} kn', color: _beaufortColor(weather.windSpeed!)),
      if (weather.windGust != null)
        (label: '阵风', value: '${weather.windGust!.toStringAsFixed(0)} kn', color: _beaufortColor(weather.windGust!)),
      if (weather.pressure != null)
        (label: '气压', value: '${weather.pressure!.round()} hPa', color: Colors.white70),
      if (weather.pressureTrend != null)
        (label: '气压趋势', value: _pressureTrendLabel(weather.pressureTrend) ?? '--',
          color: (weather.pressureTrend ?? 0) <= -6 ? AppColors.danger : Colors.white54),
      if (weather.waveHeight != null)
        (label: '浪高', value: '${weather.waveHeight!.toStringAsFixed(1)} m', color: Colors.lightBlueAccent),
    ];

    return Row(
      children: items.map((item) => Padding(
        padding: const EdgeInsets.only(right: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
            Text(item.value, style: TextStyle(color: item.color, fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      )).toList(),
    );
  }
}

// Wind flow animation (Windy/PredictWind style)
// ---------------------------------------------------------------------------

class _WindFlowCard extends StatefulWidget {
  final double windSpeed;   // knots
  final int windDir;        // degrees FROM (meteorological)
  final double? windGust;   // knots
  final List<HourlyForecast> hourly;

  const _WindFlowCard({
    required this.windSpeed,
    required this.windDir,
    required this.hourly,
    this.windGust,
  });

  @override
  State<_WindFlowCard> createState() => _WindFlowCardState();
}

class _WindFlowCardState extends State<_WindFlowCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  // Fixed random seeds — deterministic so no layout jumps on rebuild
  static final _rng = math.Random(7331);
  static const _n = 70;
  static final _xs     = List.generate(_n, (_) => _rng.nextDouble());
  static final _ys     = List.generate(_n, (_) => _rng.nextDouble());
  static final _phases = List.generate(_n, (_) => _rng.nextDouble());
  static final _alphas = List.generate(_n, (_) => 0.45 + _rng.nextDouble() * 0.55);

  @override
  void initState() {
    super.initState();
    // Long cycle (60 s) so the t=1→0 wrap happens rarely and is imperceptible
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    )..repeat();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _glassCard(
      padding: EdgeInsets.zero,
      radius: 16,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 230,
          width: double.infinity,
          child: AnimatedBuilder(
            animation: _anim,
            builder: (_, __) => CustomPaint(
              painter: _WindFlowPainter(
                t: _anim.value,
                windSpeed: widget.windSpeed,
                windDir: widget.windDir,
                windGust: widget.windGust,
                xs: _xs,
                ys: _ys,
                phases: _phases,
                alphas: _alphas,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WindFlowPainter extends CustomPainter {
  final double t;
  final double windSpeed;   // knots
  final int windDir;        // degrees FROM
  final double? windGust;
  final List<double> xs, ys, phases, alphas;

  const _WindFlowPainter({
    required this.t,
    required this.windSpeed,
    required this.windDir,
    required this.xs,
    required this.ys,
    required this.phases,
    required this.alphas,
    this.windGust,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Wind direction FROM → flow vector TO (in screen coords, y+ = down)
    // FROM N (0°): flow toward S → dy+
    // FROM E (90°): flow toward W → dx-
    final rad = windDir * math.pi / 180.0;
    final vx = -math.sin(rad); // normalized flow unit vector x
    final vy =  math.cos(rad); // normalized flow unit vector y

    // Speed: how many normalized screen-widths a particle travels per cycle (60s).
    // At 20 kn → 5 widths/cycle → ~0.083 widths/s → ~33px/s on a 400px canvas.
    final speedPerCycle = (windSpeed / 20.0 * 5.0).clamp(0.5, 18.0);

    // Tail length in normalized [0,1] screen coords — longer at higher speeds.
    final tailNorm = (windSpeed / 40.0 * 0.14).clamp(0.04, 0.22);

    final color = _beaufortColor(windSpeed);

    for (int i = 0; i < xs.length; i++) {
      // rawX/rawY are in "wrap-space": integer part = number of wraps,
      // fractional part = normalized screen position.
      final progress = t + phases[i];
      final rawX = xs[i] + vx * progress * speedPerCycle;
      final rawY = ys[i] + vy * progress * speedPerCycle;

      final x = (rawX % 1.0 + 1.0) % 1.0;
      final y = (rawY % 1.0 + 1.0) % 1.0;
      final px = x * size.width;
      final py = y * size.height;

      // Tail: offset in the same wrap-space, same units.
      final tailRawX = rawX - vx * tailNorm;
      final tailRawY = rawY - vy * tailNorm;
      final noWrap = rawX.floor() == tailRawX.floor() &&
                     rawY.floor() == tailRawY.floor();

      final a = alphas[i];
      if (noWrap) {
        final tx = (tailRawX % 1.0 + 1.0) % 1.0 * size.width;
        final ty = (tailRawY % 1.0 + 1.0) % 1.0 * size.height;
        canvas.drawLine(
          Offset(tx, ty),
          Offset(px, py),
          Paint()
            ..strokeWidth = 1.5
            ..style = PaintingStyle.stroke
            ..shader = LinearGradient(
              colors: [color.withOpacity(0), color.withOpacity(a * 0.80)],
            ).createShader(Rect.fromPoints(Offset(tx, ty), Offset(px, py))),
        );
      }

      canvas.drawCircle(Offset(px, py), 1.7, Paint()..color = color.withOpacity(a));
    }

    // ── Compass rose (center) ──────────────────────────────────────────────
    _paintCompass(canvas, size);

    // ── Info overlay (top-left) ────────────────────────────────────────────
    _paintInfo(canvas, size);
  }

  void _paintCompass(Canvas canvas, Size size) {
    final cx = size.width * 0.5;
    final cy = size.height * 0.5;
    const r = 46.0;

    // Background circle
    canvas.drawCircle(
      Offset(cx, cy), r,
      Paint()..color = Colors.black.withOpacity(0.40),
    );
    canvas.drawCircle(
      Offset(cx, cy), r,
      Paint()
        ..color = Colors.white.withOpacity(0.10)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6,
    );

    // Tick marks at 45° intervals
    for (int deg = 0; deg < 360; deg += 45) {
      final a = deg * math.pi / 180;
      final inner = deg % 90 == 0 ? r - 8.0 : r - 5.0;
      canvas.drawLine(
        Offset(cx + math.sin(a) * inner, cy - math.cos(a) * inner),
        Offset(cx + math.sin(a) * r,     cy - math.cos(a) * r),
        Paint()
          ..color = Colors.white.withOpacity(deg % 90 == 0 ? 0.55 : 0.25)
          ..strokeWidth = deg % 90 == 0 ? 1.2 : 0.7,
      );
    }

    // Cardinal labels
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (final (label, deg) in [('N', 0), ('E', 90), ('S', 180), ('W', 270)]) {
      final a = deg * math.pi / 180.0;
      tp.text = TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white.withOpacity(0.60),
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      );
      tp.layout();
      final lx = cx + math.sin(a) * (r - 13) - tp.width / 2;
      final ly = cy - math.cos(a) * (r - 13) - tp.height / 2;
      tp.paint(canvas, Offset(lx, ly));
    }

    // Wind direction arrow — FROM direction (meteorological convention)
    // The tail of the arrow points to where wind comes FROM
    final arrowRad = windDir * math.pi / 180.0;
    final arrowLen = r * 0.55;
    final tipX = cx + math.sin(arrowRad) * arrowLen;
    final tipY = cy - math.cos(arrowRad) * arrowLen;
    // Shaft: center → tip (tip = FROM direction)
    final arrowColor = _beaufortColor(windSpeed);
    canvas.drawLine(
      Offset(cx, cy),
      Offset(tipX, tipY),
      Paint()
        ..color = arrowColor.withOpacity(0.9)
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );
    // Arrowhead at tip
    final headLen = 7.0;
    for (final side in [-0.4, 0.4]) {
      final hx = tipX - math.sin(arrowRad + side) * headLen;
      final hy = tipY + math.cos(arrowRad + side) * headLen;
      canvas.drawLine(
        Offset(tipX, tipY), Offset(hx, hy),
        Paint()
          ..color = arrowColor.withOpacity(0.9)
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round,
      );
    }

    // Speed text in center
    tp.text = TextSpan(
      text: '${windSpeed.round()}',
      style: TextStyle(
        color: arrowColor,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
    );
    tp.layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2 - 6));

    tp.text = TextSpan(
      text: 'kn',
      style: const TextStyle(color: Colors.white54, fontSize: 9),
    );
    tp.layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy + 8));
  }

  void _paintInfo(Canvas canvas, Size size) {
    final force = _bft(windSpeed);
    final dirLabel = windDirectionLabel(windDir);
    final gustStr  = windGust != null ? '  阵 ${windGust!.round()}kn' : '';
    final color    = _beaufortColor(windSpeed);

    // Background pill
    final tp = TextPainter(textDirection: TextDirection.ltr);
    tp.text = TextSpan(
      text: 'FROM $dirLabel · B$force$gustStr',
      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
    );
    tp.layout();
    final padH = 10.0;
    final padV = 6.0;
    final pillRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(12, 12, tp.width + padH * 2, tp.height + padV * 2),
      const Radius.circular(20),
    );
    canvas.drawRRect(pillRect, Paint()..color = Colors.black.withOpacity(0.45));
    canvas.drawRRect(pillRect,
      Paint()
        ..color = color.withOpacity(0.30)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
    tp.paint(canvas, Offset(12 + padH, 12 + padV));
  }

  static int _bft(double kn) {
    if (kn < 1)  return 0; if (kn < 4)  return 1; if (kn < 7)  return 2;
    if (kn < 11) return 3; if (kn < 17) return 4; if (kn < 22) return 5;
    if (kn < 28) return 6; if (kn < 34) return 7; if (kn < 41) return 8;
    if (kn < 48) return 9; if (kn < 56) return 10; if (kn < 64) return 11;
    return 12;
  }

  @override
  bool shouldRepaint(_WindFlowPainter old) =>
      old.t != t || old.windDir != windDir || old.windSpeed != windSpeed;
}

// ---------------------------------------------------------------------------
// Pressure sparkline
// ---------------------------------------------------------------------------

class _PressureSparkline extends StatelessWidget {
  final List<HourlyForecast> hourly;
  const _PressureSparkline({required this.hourly});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PressureSparklinePainter(hourly: hourly),
      size: Size.infinite,
    );
  }
}

class _PressureSparklinePainter extends CustomPainter {
  final List<HourlyForecast> hourly;
  const _PressureSparklinePainter({required this.hourly});

  @override
  void paint(Canvas canvas, Size size) {
    final pts = hourly
        .where((h) => h.pressure != null)
        .toList();
    if (pts.length < 2) return;

    final pressures = pts.map((h) => h.pressure!).toList();
    final pMin = pressures.reduce(math.min);
    final pMax = pressures.reduce(math.max);
    final pRange = (pMax - pMin).clamp(2.0, double.infinity);

    const padT = 4.0;
    const padB = 20.0;
    final chartH = size.height - padT - padB;
    final stepX  = size.width / (pts.length - 1);

    double px(int i) => i * stepX;
    double py(double p) => padT + chartH * (1 - (p - pMin) / pRange);

    // Build path
    final path = Path()..moveTo(px(0), py(pressures[0]));
    for (int i = 1; i < pts.length; i++) {
      // Smooth cubic bezier
      final x0 = px(i - 1), y0 = py(pressures[i - 1]);
      final x1 = px(i),     y1 = py(pressures[i]);
      final cp = (x0 + x1) / 2;
      path.cubicTo(cp, y0, cp, y1, x1, y1);
    }

    // Filled area
    final fillPath = Path.from(path)
      ..lineTo(px(pts.length - 1), size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF64D2FF).withOpacity(0.30),
            const Color(0xFF64D2FF).withOpacity(0.02),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    // Line — color-coded: red where falling fast, green where stable/rising
    for (int i = 1; i < pts.length; i++) {
      final delta = pressures[i] - pressures[i - 1];
      Color lineColor;
      if (delta < -2)      lineColor = const Color(0xFFFF453A);
      else if (delta < -1) lineColor = const Color(0xFFFF9F0A);
      else if (delta > 1)  lineColor = const Color(0xFF30D158);
      else                 lineColor = const Color(0xFF64D2FF);

      final segPath = Path()
        ..moveTo(px(i - 1), py(pressures[i - 1]));
      final cp = (px(i - 1) + px(i)) / 2;
      segPath.cubicTo(cp, py(pressures[i - 1]), cp, py(pressures[i]), px(i), py(pressures[i]));
      canvas.drawPath(
        segPath,
        Paint()
          ..color = lineColor.withOpacity(0.85)
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // X-axis time labels + current value label
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (int i = 0; i < pts.length; i += 4) {
      final hour = pts[i].time.toLocal().hour;
      tp.text = TextSpan(
        text: '${hour}h',
        style: const TextStyle(color: Colors.white38, fontSize: 9),
      );
      tp.layout();
      tp.paint(canvas, Offset(px(i) - tp.width / 2, size.height - 16));
    }

    // Current pressure dot + label
    final curP = pressures[0];
    canvas.drawCircle(
      Offset(px(0), py(curP)), 4,
      Paint()..color = const Color(0xFF64D2FF),
    );
    tp.text = TextSpan(
      text: '${curP.round()} hPa',
      style: const TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.w600),
    );
    tp.layout();
    tp.paint(canvas, Offset(6, py(curP) - tp.height - 2));
  }

  @override
  bool shouldRepaint(_PressureSparklinePainter old) => old.hourly != hourly;
}

class _BeaufortChip extends StatelessWidget {
  final Color color;
  final String label;
  const _BeaufortChip({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
      ],
    );
  }
}

/// Returns a human-readable pressure trend label.
/// [trend] is hPa/3h (positive = rising).
String? _pressureTrendLabel(double? trend) {
  if (trend == null) return null;
  final abs = trend.abs();
  // IMO gale warning threshold: ≥ 6 hPa/3h
  if (trend <= -6) return '↓↓ ${trend.toStringAsFixed(1)} hPa/3h  急降！';
  if (trend <= -3) return '↓ ${trend.toStringAsFixed(1)} hPa/3h  下降';
  if (trend >= 6)  return '↑↑ +${trend.toStringAsFixed(1)} hPa/3h  急升';
  if (trend >= 3)  return '↑ +${trend.toStringAsFixed(1)} hPa/3h  上升';
  if (abs < 1)     return '→ 稳定';
  return trend > 0
      ? '↑ +${trend.toStringAsFixed(1)} hPa/3h'
      : '↓ ${trend.toStringAsFixed(1)} hPa/3h';
}

Color _beaufortColor(double kn) {
  if (kn >= 34) return const Color(0xFFFF453A); // 8+ Beaufort
  if (kn >= 22) return const Color(0xFFFF9F0A); // 6-7
  if (kn >= 11) return const Color(0xFFFFD60A); // 4-5
  return const Color(0xFF30D158);               // 0-3
}

class _WindBarChart extends StatelessWidget {
  final List<HourlyForecast> data;
  const _WindBarChart({required this.data});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _WindBarPainter(data: data),
      size: Size.infinite,
    );
  }
}

class _WindBarPainter extends CustomPainter {
  final List<HourlyForecast> data;
  const _WindBarPainter({required this.data});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final maxWind = data
        .map((h) => h.windSpeed ?? 0.0)
        .reduce(math.max)
        .clamp(10.0, double.infinity);

    const bottomPad = 28.0;
    const topPad = 10.0;
    final chartH = size.height - bottomPad - topPad;

    final barW = (size.width / data.length) * 0.6;
    final gap = (size.width / data.length) * 0.4;

    final labelPaint = TextPainter(textDirection: TextDirection.ltr);

    for (int i = 0; i < data.length; i++) {
      final kn = data[i].windSpeed ?? 0.0;
      final barH = (kn / maxWind) * chartH;
      final x = i * (barW + gap) + gap / 2;
      final y = topPad + (chartH - barH);

      final color = _beaufortColor(kn);
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;

      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barW, barH),
        const Radius.circular(3),
      );
      canvas.drawRRect(rrect, paint);

      // X-axis label — every 3 hours
      if (i % 3 == 0) {
        final hour = data[i].time.toLocal().hour;
        labelPaint.text = TextSpan(
          text: '${hour}h',
          style: const TextStyle(color: Colors.white38, fontSize: 9),
        );
        labelPaint.layout();
        labelPaint.paint(
          canvas,
          Offset(x + barW / 2 - labelPaint.width / 2, size.height - 18),
        );
      }
    }

    // Y-axis labels
    final yPaint = TextPainter(textDirection: TextDirection.ltr);
    for (final yVal in [0, (maxWind / 2).round(), maxWind.round()]) {
      final y = topPad + chartH - (yVal / maxWind) * chartH;
      yPaint.text = TextSpan(
        text: '$yVal',
        style: const TextStyle(color: Colors.white38, fontSize: 9),
      );
      yPaint.layout();
      yPaint.paint(canvas, Offset(0, y - 5));

      // Grid line
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = Colors.white.withOpacity(0.06)
          ..strokeWidth = 0.5,
      );
    }
  }

  @override
  bool shouldRepaint(_WindBarPainter old) => old.data != data;
}

// ---------------------------------------------------------------------------
// TAB 3 — 浪 (Waves)
// ---------------------------------------------------------------------------

class _WavesTab extends StatelessWidget {
  final List<HourlyForecast> hourly;
  const _WavesTab({required this.hourly});

  @override
  Widget build(BuildContext context) {
    final data = hourly.take(24).toList();
    final hasWaveData = data.any((h) => (h.waveHeight ?? 0) > 0);

    if (data.isEmpty || !hasWaveData) {
      return _EmptyPlaceholder(message: '无浪高数据');
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: _glassCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '未来24小时浪高 (m)',
              style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 220,
              child: _WaveLineChart(data: data),
            ),
          ],
        ),
      ),
    );
  }
}

class _WaveLineChart extends StatelessWidget {
  final List<HourlyForecast> data;
  const _WaveLineChart({required this.data});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _WaveLinePainter(data: data),
      size: Size.infinite,
    );
  }
}

class _WaveLinePainter extends CustomPainter {
  final List<HourlyForecast> data;
  const _WaveLinePainter({required this.data});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final heights = data.map((h) => h.waveHeight ?? 0.0).toList();
    final maxH = heights.reduce(math.max).clamp(0.1, double.infinity);

    const bottomPad = 28.0;
    const topPad = 10.0;
    final chartH = size.height - bottomPad - topPad;
    final stepX = size.width / (data.length - 1).clamp(1, 999);

    Offset point(int i) {
      final x = i * stepX;
      final y = topPad + chartH - (heights[i] / maxH) * chartH;
      return Offset(x, y);
    }

    // Fill path
    final fillPath = Path();
    fillPath.moveTo(0, size.height - bottomPad);
    for (int i = 0; i < data.length; i++) {
      final p = point(i);
      if (i == 0) {
        fillPath.lineTo(p.dx, p.dy);
      } else {
        final prev = point(i - 1);
        final cpX = (prev.dx + p.dx) / 2;
        fillPath.cubicTo(cpX, prev.dy, cpX, p.dy, p.dx, p.dy);
      }
    }
    fillPath.lineTo(size.width, size.height - bottomPad);
    fillPath.close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF00D9FF).withOpacity(0.35),
            const Color(0xFF00D9FF).withOpacity(0.05),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    // Line path
    final linePath = Path();
    for (int i = 0; i < data.length; i++) {
      final p = point(i);
      if (i == 0) {
        linePath.moveTo(p.dx, p.dy);
      } else {
        final prev = point(i - 1);
        final cpX = (prev.dx + p.dx) / 2;
        linePath.cubicTo(cpX, prev.dy, cpX, p.dy, p.dx, p.dy);
      }
    }

    canvas.drawPath(
      linePath,
      Paint()
        ..color = const Color(0xFF00D9FF)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // X-axis labels and Y-axis
    final labelPaint = TextPainter(textDirection: TextDirection.ltr);
    for (int i = 0; i < data.length; i += 3) {
      final hour = data[i].time.toLocal().hour;
      labelPaint.text = TextSpan(
        text: '${hour}h',
        style: const TextStyle(color: Colors.white38, fontSize: 9),
      );
      labelPaint.layout();
      labelPaint.paint(canvas, Offset(i * stepX - labelPaint.width / 2, size.height - 18));
    }

    for (final val in [0.0, maxH / 2, maxH]) {
      final y = topPad + chartH - (val / maxH) * chartH;
      labelPaint.text = TextSpan(
        text: val.toStringAsFixed(1),
        style: const TextStyle(color: Colors.white38, fontSize: 9),
      );
      labelPaint.layout();
      labelPaint.paint(canvas, Offset(0, y - 5));

      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = Colors.white.withOpacity(0.06)
          ..strokeWidth = 0.5,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveLinePainter old) => old.data != data;
}

// ---------------------------------------------------------------------------
// TAB 4 — 潮汐 (Tides)
// ---------------------------------------------------------------------------

class _TidesTab extends StatelessWidget {
  final List<TideEntry> tides;
  const _TidesTab({required this.tides});

  @override
  Widget build(BuildContext context) {
    if (tides.isEmpty) {
      return _EmptyPlaceholder(message: '需要 WorldTides API Key\n请在设置中配置 WorldTides 密钥');
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _glassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '潮汐预测',
                  style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 220,
                  child: _TideCurveChart(tides: tides),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Tide list
          ...tides.take(8).map((t) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _glassCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    t.isHighTide ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                    size: 16,
                    color: t.isHighTide ? const Color(0xFF00D9FF) : AppColors.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    t.isHighTide ? '高潮' : '低潮',
                    style: TextStyle(
                      color: t.isHighTide ? const Color(0xFF00D9FF) : AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    DateFormat('MM/dd HH:mm').format(t.time.toLocal()),
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                  const Spacer(),
                  Text(
                    '${t.height.toStringAsFixed(2)} m',
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          )),
        ],
      ),
    );
  }
}

class _TideCurveChart extends StatelessWidget {
  final List<TideEntry> tides;
  const _TideCurveChart({required this.tides});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _TideCurvePainter(tides: tides),
      size: Size.infinite,
    );
  }
}

class _TideCurvePainter extends CustomPainter {
  final List<TideEntry> tides;
  const _TideCurvePainter({required this.tides});

  @override
  void paint(Canvas canvas, Size size) {
    if (tides.isEmpty) return;

    // Find tides for today
    final now = DateTime.now();
    final todayTides = tides.where((t) => t.time.toLocal().day == now.day).toList();
    final workingTides = todayTides.isEmpty ? tides.take(4).toList() : todayTides;
    if (workingTides.isEmpty) return;

    final heights = workingTides.map((t) => t.height).toList();
    final minH = heights.reduce(math.min);
    final maxH = heights.reduce(math.max);
    final range = (maxH - minH).clamp(0.1, double.infinity);

    const bottomPad = 28.0;
    const topPad = 10.0;
    final chartH = size.height - bottomPad - topPad;

    // Map time to x: 0–24h range
    final dayStart = DateTime(now.year, now.month, now.day);
    final dayEnd = dayStart.add(const Duration(hours: 24));

    Offset tideToPoint(TideEntry t) {
      final xFrac = (t.time.toLocal().difference(dayStart).inMinutes /
              dayEnd.difference(dayStart).inMinutes)
          .clamp(0.0, 1.0);
      final yFrac = (t.height - minH) / range;
      return Offset(
        xFrac * size.width,
        topPad + chartH - yFrac * chartH,
      );
    }

    final points = workingTides.map(tideToPoint).toList();

    // Build smooth path using cubic bezier
    final path = Path();
    if (points.length == 1) {
      path.moveTo(0, points[0].dy);
      path.lineTo(size.width, points[0].dy);
    } else {
      path.moveTo(0, points[0].dy);
      for (int i = 0; i < points.length - 1; i++) {
        final p0 = points[i];
        final p1 = points[i + 1];
        final cpX = (p0.dx + p1.dx) / 2;
        path.cubicTo(cpX, p0.dy, cpX, p1.dy, p1.dx, p1.dy);
      }
      // Extend to edges
      if (points.last.dx < size.width) {
        path.lineTo(size.width, points.last.dy);
      }
    }

    // Fill
    final fillPath = Path.from(path);
    fillPath.lineTo(size.width, size.height - bottomPad);
    fillPath.lineTo(0, size.height - bottomPad);
    fillPath.close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF0A84FF).withOpacity(0.30),
            const Color(0xFF0A84FF).withOpacity(0.04),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    // Line
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF0A84FF)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // Tide markers
    final labelPaint = TextPainter(textDirection: TextDirection.ltr);
    for (int i = 0; i < workingTides.length; i++) {
      final t = workingTides[i];
      final p = points[i];
      final color = t.isHighTide ? const Color(0xFF00D9FF) : AppColors.textSecondary;

      // Dot
      canvas.drawCircle(p, 5, Paint()..color = color);
      canvas.drawCircle(p, 5, Paint()
        ..color = Colors.black.withOpacity(0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5);

      // Label
      final label = '${t.isHighTide ? '高' : '低'} ${t.height.toStringAsFixed(1)}m';
      labelPaint.text = TextSpan(
        text: label,
        style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w600),
      );
      labelPaint.layout();
      final lx = (p.dx - labelPaint.width / 2).clamp(0.0, size.width - labelPaint.width);
      final ly = t.isHighTide ? p.dy - 18 : p.dy + 6;
      labelPaint.paint(canvas, Offset(lx, ly.clamp(topPad, size.height - bottomPad - 12)));
    }

    // X-axis time labels
    for (int h = 0; h <= 24; h += 6) {
      final x = (h / 24.0) * size.width;
      labelPaint.text = TextSpan(
        text: '${h}h',
        style: const TextStyle(color: Colors.white38, fontSize: 9),
      );
      labelPaint.layout();
      labelPaint.paint(canvas, Offset(x - labelPaint.width / 2, size.height - 18));
    }
  }

  @override
  bool shouldRepaint(_TideCurvePainter old) => old.tides != tides;
}

// ---------------------------------------------------------------------------
// TAB 5 — 预报 (Forecast)
// ---------------------------------------------------------------------------

class _ForecastTab extends StatelessWidget {
  final List<DailyForecast> daily;
  const _ForecastTab({required this.daily});

  String _weekDay(DateTime date) {
    const days = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final now = DateTime.now();
    if (date.day == now.day && date.month == now.month) return '今天';
    if (date.difference(DateTime(now.year, now.month, now.day)).inDays == 1) return '明天';
    return days[(date.weekday - 1) % 7];
  }

  IconData _forecastIcon(String? symbolCode) {
    if (symbolCode == null) return Icons.wb_sunny_rounded;
    if (symbolCode.contains('sun') || symbolCode.contains('clear')) return Icons.wb_sunny_rounded;
    if (symbolCode.contains('rain') || symbolCode.contains('shower')) return Icons.umbrella_rounded;
    if (symbolCode.contains('cloud') || symbolCode.contains('overcast')) return Icons.cloud_rounded;
    if (symbolCode.contains('thunder')) return Icons.bolt_rounded;
    if (symbolCode.contains('snow')) return Icons.ac_unit_rounded;
    if (symbolCode.contains('fog')) return Icons.foggy;
    return Icons.wb_cloudy_rounded;
  }

  @override
  Widget build(BuildContext context) {
    if (daily.isEmpty) {
      return _EmptyPlaceholder(message: '暂无预报数据');
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      itemCount: daily.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final d = daily[i];
        final day = _weekDay(d.date);
        final icon = _forecastIcon(d.symbolCode);
        final tempStr = '${d.tempMax?.round() ?? '--'}° / ${d.tempMin?.round() ?? '--'}°';
        final windStr = d.windSpeedMax != null
            ? '${d.windSpeedMax!.toStringAsFixed(0)} kn'
            : '--';
        final waveStr = d.waveHeightMax != null
            ? '≈${d.waveHeightMax!.toStringAsFixed(1)} m'
            : null;

        return _glassCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              // Day
              SizedBox(
                width: 38,
                child: Text(
                  day,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Icon
              Icon(icon, color: Colors.white70, size: 20),
              const SizedBox(width: 10),
              // Temp
              Expanded(
                child: Text(
                  tempStr,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
              // Wind
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.air_rounded, size: 12, color: Colors.white54),
                  const SizedBox(width: 3),
                  Text(windStr, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
              // Wave
              if (waveStr != null) ...[
                const SizedBox(width: 10),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.waves_rounded, size: 12, color: Colors.white38),
                    const SizedBox(width: 3),
                    Text(
                      waveStr,
                      style: const TextStyle(color: Colors.lightBlueAccent, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Empty placeholder
// ---------------------------------------------------------------------------

class _EmptyPlaceholder extends StatelessWidget {
  final String message;
  const _EmptyPlaceholder({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: _glassCard(
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.info_outline_rounded, color: Colors.white38, size: 40),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
