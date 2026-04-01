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
// WeatherScreen — sailing-focused, MetService only
// ---------------------------------------------------------------------------

class WeatherScreen extends ConsumerStatefulWidget {
  const WeatherScreen({super.key});

  @override
  ConsumerState<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends ConsumerState<WeatherScreen> {
  int _selectedTab = 0; // 0 = hourly, 1 = daily

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(weatherProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final weather = ref.watch(weatherProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const BackButton(color: Colors.white),
        actions: [
          if (weather.isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white70,
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
              onPressed: () => ref.read(weatherProvider.notifier).refresh(),
            ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const WeatherBackground(),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Location + fetch time
                  _LocationHeader(weather: weather),
                  const SizedBox(height: 16),

                  // Error state
                  if (weather.error != null) ...[
                    _ErrorCard(error: weather.error!),
                    const SizedBox(height: 16),
                  ],

                  // Loading hero
                  if (weather.isLoading && weather.windSpeed == null)
                    _LoadingHero()
                  else ...[
                    // HERO: wind + wave glass card
                    _WindWaveHero(weather: weather),
                    const SizedBox(height: 14),

                    // Temperature + condition
                    _TempConditionRow(weather: weather),
                    const SizedBox(height: 20),
                  ],

                  // Tab row
                  _TabRow(
                    selectedTab: _selectedTab,
                    onTab: (i) => setState(() => _selectedTab = i),
                  ),
                  const SizedBox(height: 12),

                  // Forecast content
                  if (_selectedTab == 0)
                    _HourlyForecastSection(hourly: weather.hourly)
                  else
                    _DailyForecastSection(daily: weather.daily),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Location header
// ---------------------------------------------------------------------------

class _LocationHeader extends StatelessWidget {
  final WeatherState weather;
  const _LocationHeader({required this.weather});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (weather.locationLabel != null) ...[
          const Icon(Icons.location_on_rounded, size: 13, color: Colors.white70),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              weather.locationLabel!,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ] else
          const Spacer(),
        if (weather.fetchedAt != null)
          Text(
            '更新 ${DateFormat('HH:mm').format(weather.fetchedAt!.toLocal())}',
            style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 11),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Wind + Wave hero card
// ---------------------------------------------------------------------------

class _WindWaveHero extends StatelessWidget {
  final WeatherState weather;
  const _WindWaveHero({required this.weather});

  @override
  Widget build(BuildContext context) {
    final windDir = weather.windDirection;
    final windLabel = windDir != null ? windDirectionLabel(windDir) : null;
    final windStr = weather.windSpeed != null
        ? weather.windSpeed!.toStringAsFixed(1)
        : '--';
    final gustStr = weather.windGust != null
        ? weather.windGust!.toStringAsFixed(0)
        : '--';

    final waveStr = weather.waveHeight != null
        ? weather.waveHeight!.toStringAsFixed(1)
        : '--';
    final periodStr = weather.wavePeriod != null
        ? '${weather.wavePeriod!.toStringAsFixed(0)}s'
        : '--';
    final swellStr = weather.swellHeight != null
        ? weather.swellHeight!.toStringAsFixed(1)
        : '--';
    final swellDirLabel = weather.swellDirection != null
        ? windDirectionLabel(weather.swellDirection!)
        : '--';

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.20)),
          ),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Wind column
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.air_rounded, size: 14, color: Colors.white60),
                        const SizedBox(width: 6),
                        const Text('风速', style: TextStyle(color: Colors.white60, fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // Wind direction arrow
                        if (windDir != null)
                          Padding(
                            padding: const EdgeInsets.only(right: 8, bottom: 2),
                            child: Transform.rotate(
                              angle: windDir * math.pi / 180,
                              child: const Icon(
                                Icons.navigation_rounded,
                                color: Colors.cyanAccent,
                                size: 22,
                              ),
                            ),
                          ),
                        Text(
                          windStr,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 36,
                            fontWeight: FontWeight.w300,
                            height: 1.0,
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.only(bottom: 4, left: 4),
                          child: Text('kn',
                              style: TextStyle(color: Colors.white60, fontSize: 14)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (windLabel != null || windDir != null)
                      Text(
                        '${windLabel ?? ''}${windDir != null ? ' · ${windDir}°' : ''}',
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      '阵风: $gustStr kn',
                      style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                    ),
                  ],
                ),
              ),

              // Divider
              Container(
                width: 1,
                height: 90,
                margin: const EdgeInsets.symmetric(horizontal: 14),
                color: Colors.white.withOpacity(0.15),
              ),

              // Wave column
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.waves_rounded, size: 14, color: Colors.white60),
                        const SizedBox(width: 6),
                        const Text('海浪', style: TextStyle(color: Colors.white60, fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          waveStr,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 36,
                            fontWeight: FontWeight.w300,
                            height: 1.0,
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.only(bottom: 4, left: 4),
                          child: Text('m',
                              style: TextStyle(color: Colors.white60, fontSize: 14)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '周期: $periodStr',
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '涌浪: $swellStr m $swellDirLabel',
                      style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                    ),
                  ],
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
// Temperature + condition row
// ---------------------------------------------------------------------------

class _TempConditionRow extends StatelessWidget {
  final WeatherState weather;
  const _TempConditionRow({required this.weather});

  @override
  Widget build(BuildContext context) {
    final code = weather.weatherCode ?? 0;
    return Row(
      children: [
        Text(
          weather.temperature != null
              ? '${weather.temperature!.round()}°C'
              : '--°C',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.w300,
          ),
        ),
        const SizedBox(width: 12),
        Icon(iconForCode(code), color: Colors.white70, size: 20),
        const SizedBox(width: 6),
        Text(
          weather.description ?? (weather.isLoading ? '加载中…' : '暂无数据'),
          style: const TextStyle(color: Colors.white70, fontSize: 16),
        ),
        if (weather.feelsLike != null) ...[
          const SizedBox(width: 10),
          Text(
            '体感 ${weather.feelsLike!.round()}°',
            style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 13),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Loading hero
// ---------------------------------------------------------------------------

class _LoadingHero extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.15)),
          ),
          padding: const EdgeInsets.all(40),
          child: const Center(
            child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab row
// ---------------------------------------------------------------------------

class _TabRow extends StatelessWidget {
  final int selectedTab;
  final ValueChanged<int> onTab;

  const _TabRow({required this.selectedTab, required this.onTab});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _TabPill(label: '小时预报', selected: selectedTab == 0, onTap: () => onTab(0)),
        const SizedBox(width: 8),
        _TabPill(label: '日预报', selected: selectedTab == 1, onTap: () => onTab(1)),
      ],
    );
  }
}

class _TabPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TabPill({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? Colors.cyanAccent.withOpacity(0.18)
              : Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? Colors.cyanAccent.withOpacity(0.5)
                : Colors.white.withOpacity(0.15),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.cyanAccent : Colors.white60,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hourly forecast section
// ---------------------------------------------------------------------------

class _HourlyForecastSection extends StatelessWidget {
  final List<HourlyForecast> hourly;
  const _HourlyForecastSection({required this.hourly});

  @override
  Widget build(BuildContext context) {
    if (hourly.isEmpty) {
      return _ForecastEmpty(message: '预报数据加载中…\nMetService 未返回小时预报');
    }

    final now = DateTime.now();

    return SizedBox(
      height: 160,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        itemCount: hourly.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final h = hourly[i];
          final isCurrent = h.time.hour == now.hour &&
              h.time.day == now.day &&
              h.time.month == now.month;
          return _HourlySlot(forecast: h, isCurrent: isCurrent);
        },
      ),
    );
  }
}

class _HourlySlot extends StatelessWidget {
  final HourlyForecast forecast;
  final bool isCurrent;

  const _HourlySlot({required this.forecast, required this.isCurrent});

  @override
  Widget build(BuildContext context) {
    final windStr = forecast.windSpeed != null
        ? '${forecast.windSpeed!.toStringAsFixed(0)}kn'
        : '--';
    final waveStr = forecast.waveHeight != null
        ? '≈${forecast.waveHeight!.toStringAsFixed(1)}m'
        : '--';
    final precipStr = forecast.precip != null && forecast.precip! > 0.05
        ? '${forecast.precip!.toStringAsFixed(1)}mm'
        : '0mm';
    final timeStr = DateFormat('HH:mm').format(forecast.time.toLocal());

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          width: 76,
          decoration: BoxDecoration(
            color: isCurrent
                ? Colors.cyanAccent.withOpacity(0.10)
                : Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isCurrent
                  ? Colors.cyanAccent.withOpacity(0.5)
                  : Colors.white.withOpacity(0.12),
              width: isCurrent ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                timeStr,
                style: TextStyle(
                  color: isCurrent ? Colors.cyanAccent : Colors.white60,
                  fontSize: 12,
                  fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
              const SizedBox(height: 6),
              // Wind direction arrow
              if (forecast.windDir != null)
                Transform.rotate(
                  angle: forecast.windDir! * math.pi / 180,
                  child: Icon(
                    Icons.navigation_rounded,
                    color: isCurrent ? Colors.cyanAccent : Colors.white70,
                    size: 18,
                  ),
                )
              else
                const Icon(Icons.remove_rounded, color: Colors.white30, size: 18),
              const SizedBox(height: 4),
              Text(
                windStr,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                waveStr,
                style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11),
              ),
              const SizedBox(height: 2),
              Text(
                precipStr,
                style: TextStyle(color: Colors.lightBlueAccent.withOpacity(0.7), fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Daily forecast section
// ---------------------------------------------------------------------------

class _DailyForecastSection extends StatelessWidget {
  final List<DailyForecast> daily;
  const _DailyForecastSection({required this.daily});

  @override
  Widget build(BuildContext context) {
    if (daily.isEmpty) {
      return _ForecastEmpty(message: '预报数据加载中…\nMetService 未返回日预报');
    }

    return Column(
      children: daily.map((d) => _DailyRow(forecast: d)).toList(),
    );
  }
}

class _DailyRow extends StatelessWidget {
  final DailyForecast forecast;
  const _DailyRow({required this.forecast});

  String _weekDay(DateTime date) {
    const days = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final now = DateTime.now();
    if (date.day == now.day && date.month == now.month) return '今天';
    // weekday: 1=Mon, 7=Sun
    return days[(date.weekday - 1) % 7];
  }

  @override
  Widget build(BuildContext context) {
    final tempStr = '${forecast.tempMax?.round() ?? '--'}°/${forecast.tempMin?.round() ?? '--'}°';
    final windStr = forecast.windSpeedMax != null
        ? '${forecast.windSpeedMax!.toStringAsFixed(0)}kn'
        : '--';
    final waveStr = forecast.waveHeightMax != null
        ? '≈${forecast.waveHeightMax!.toStringAsFixed(1)}m'
        : '--';
    final precipStr = forecast.precipTotal != null
        ? '💧${forecast.precipTotal!.toStringAsFixed(1)}mm'
        : '';
    final windDir = forecast.windDirDominant;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
          ),
          child: Row(
            children: [
              // Day label
              SizedBox(
                width: 40,
                child: Text(
                  _weekDay(forecast.date),
                  style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 10),

              // Condition icon
              Icon(
                iconForCode(forecast.symbolCode != null ? 1 : 0),
                size: 18,
                color: Colors.white60,
              ),
              const SizedBox(width: 10),

              // Temp
              Expanded(
                child: Text(
                  tempStr,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),

              // Wind arrow + speed
              if (windDir != null)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Transform.rotate(
                    angle: windDir * math.pi / 180,
                    child: const Icon(Icons.navigation_rounded, color: Colors.white60, size: 14),
                  ),
                ),
              Text(
                windStr,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(width: 10),

              // Wave
              Text(
                waveStr,
                style: TextStyle(color: Colors.lightBlueAccent.withOpacity(0.8), fontSize: 12),
              ),
              const SizedBox(width: 8),

              // Precip
              if (precipStr.isNotEmpty)
                Text(
                  precipStr,
                  style: const TextStyle(color: Colors.lightBlueAccent, fontSize: 11),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty forecast placeholder
// ---------------------------------------------------------------------------

class _ForecastEmpty extends StatelessWidget {
  final String message;
  const _ForecastEmpty({required this.message});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
          ),
          child: Center(
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 13),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Error card
// ---------------------------------------------------------------------------

class _ErrorCard extends StatelessWidget {
  final String error;
  const _ErrorCard({required this.error});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.danger.withOpacity(0.15),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.danger.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.white70, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  error,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
