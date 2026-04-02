import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/models/weather_state.dart';
import '../../../core/providers/weather_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../home/widgets/weather_background.dart';

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
          else
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
              onPressed: () => ref.read(weatherProvider.notifier).refresh(),
            ),
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
                      _WindTab(hourly: weather.hourly),
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

  Color _riskColor(double? windKn) {
    if (windKn == null) return AppColors.success;
    if (windKn >= 34) return AppColors.danger;
    if (windKn >= 22) return const Color(0xFFFF9F0A); // amber
    return AppColors.success;
  }

  String _riskText(double? windKn) {
    if (windKn == null) return '海况良好';
    if (windKn >= 34) return '警告：强风浪';
    if (windKn >= 22) return '注意：风力较强';
    return '海况良好';
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
                        Text(
                          '${windKn.toStringAsFixed(0)} kn',
                          style: TextStyle(color: riskColor.withOpacity(0.8), fontSize: 13),
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
                  sub: windDir != null ? '$windLabel · ${windDir}°' : null,
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
                  sub: weather.feelsLike != null
                      ? '体感 ${weather.feelsLike!.round()}°'
                      : null,
                ),
                _ConditionCell(
                  icon: Icons.speed_rounded,
                  label: '气压',
                  value: '--',
                  sub: null,
                ),
                _ConditionCell(
                  icon: Icons.visibility_rounded,
                  label: '能见度',
                  value: '--',
                  sub: null,
                ),
                _ConditionCell(
                  icon: Icons.water_drop_rounded,
                  label: '湿度',
                  value: '--',
                  sub: weather.precipitation != null && weather.precipitation! > 0
                      ? '降水 ${weather.precipitation!.toStringAsFixed(1)}mm'
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

  const _ConditionCell({
    required this.icon,
    required this.label,
    required this.value,
    this.sub,
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
              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10),
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
  final List<HourlyForecast> hourly;
  const _WindTab({required this.hourly});

  @override
  Widget build(BuildContext context) {
    // Take next 24 hours
    final data = hourly.take(24).toList();

    if (data.isEmpty) {
      return _EmptyPlaceholder(message: '暂无风速数据');
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                SizedBox(
                  height: 180,
                  child: _WindBarChart(data: data),
                ),
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
                Row(
                  children: [
                    _BeaufortChip(color: const Color(0xFF30D158), label: '0-3级 (轻风)'),
                    const SizedBox(width: 8),
                    _BeaufortChip(color: const Color(0xFFFFD60A), label: '4-5级 (中风)'),
                    const SizedBox(width: 8),
                    _BeaufortChip(color: const Color(0xFFFF9F0A), label: '6-7级 (强风)'),
                    const SizedBox(width: 8),
                    _BeaufortChip(color: const Color(0xFFFF453A), label: '8+级 (暴风)'),
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
