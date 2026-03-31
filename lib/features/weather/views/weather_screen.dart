import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/models/weather_state.dart';
import '../../../core/providers/weather_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../home/widgets/weather_background.dart';

class WeatherScreen extends ConsumerWidget {
  const WeatherScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HeroSection(weather: weather),
                  const SizedBox(height: 28),
                  if (weather.condition != null) ...[
                    _MetricsGrid(weather: weather),
                    const SizedBox(height: 20),
                  ],
                  if (weather.error != null) _ErrorCard(error: weather.error!),
                  if (!weather.isLoading && weather.condition == null && weather.error == null)
                    const _EmptyCard(),
                  if (weather.fetchedAt != null) ...[
                    const SizedBox(height: 16),
                    Center(
                      child: Text(
                        '更新于 ${DateFormat('HH:mm').format(weather.fetchedAt!.toLocal())}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.45),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
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
// Hero — large temperature + condition
// ---------------------------------------------------------------------------

class _HeroSection extends StatelessWidget {
  final WeatherState weather;
  const _HeroSection({required this.weather});

  @override
  Widget build(BuildContext context) {
    final code = weather.weatherCode ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 8),
        if (weather.locationLabel != null)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.location_on_rounded,
                  size: 13, color: Colors.white70),
              const SizedBox(width: 4),
              Text(
                weather.locationLabel!,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        const SizedBox(height: 20),
        // Big temperature
        Text(
          weather.temperature != null
              ? '${weather.temperature!.round()}°'
              : '--°',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 88,
            fontWeight: FontWeight.w200,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 6),
        // Condition icon + description
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(iconForCode(code), color: Colors.white, size: 22),
            const SizedBox(width: 8),
            Text(
              weather.description ?? '正在获取…',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w300,
              ),
            ),
          ],
        ),
        if (weather.feelsLike != null) ...[
          const SizedBox(height: 6),
          Text(
            '体感 ${weather.feelsLike!.round()}°',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 15,
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Metrics grid
// ---------------------------------------------------------------------------

class _MetricsGrid extends StatelessWidget {
  final WeatherState weather;
  const _MetricsGrid({required this.weather});

  @override
  Widget build(BuildContext context) {
    final windDir = weather.windDirection;
    final windLabel = windDir != null ? windDirectionLabel(windDir) : null;
    final windStr = weather.windSpeed != null
        ? '${weather.windSpeed!.toStringAsFixed(1)} kn'
        : '--';

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.6,
      children: [
        _MetricCard(
          icon: Icons.air_rounded,
          label: '风速',
          value: windStr,
          sub: windLabel != null ? '$windLabel ${windDir!}°' : null,
        ),
        _MetricCard(
          icon: Icons.umbrella_rounded,
          label: '降水量',
          value: weather.precipitation != null
              ? '${weather.precipitation!.toStringAsFixed(1)} mm'
              : '-- mm',
        ),
        _MetricCard(
          icon: Icons.thermostat_rounded,
          label: '气温',
          value: weather.temperature != null
              ? '${weather.temperature!.toStringAsFixed(1)}°C'
              : '--°C',
          sub: weather.feelsLike != null
              ? '体感 ${weather.feelsLike!.toStringAsFixed(1)}°C'
              : null,
        ),
        _MetricCard(
          icon: Icons.explore_rounded,
          label: '风向',
          value: windLabel ?? '--',
          sub: windDir != null ? '$windDir°' : null,
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? sub;

  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    this.sub,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.12),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.18)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, size: 14, color: Colors.white60),
                  const SizedBox(width: 6),
                  Text(label,
                      style: const TextStyle(
                          color: Colors.white60, fontSize: 11)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w400)),
                  if (sub != null)
                    Text(sub!,
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.55),
                            fontSize: 11)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Error / empty states
// ---------------------------------------------------------------------------

class _ErrorCard extends StatelessWidget {
  final String error;
  const _ErrorCard({required this.error});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.danger.withOpacity(0.15),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.danger.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: Colors.white70, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  error,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.15)),
          ),
          child: Column(
            children: [
              const Icon(Icons.cloud_off_rounded,
                  color: Colors.white38, size: 36),
              const SizedBox(height: 12),
              const Text(
                '暂无天气数据',
                style: TextStyle(color: Colors.white60, fontSize: 15),
              ),
              const SizedBox(height: 6),
              Text(
                '需要网络连接和定位权限',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.4), fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
