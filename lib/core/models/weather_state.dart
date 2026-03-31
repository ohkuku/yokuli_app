import 'package:flutter/material.dart';
import 'dart:math' as math;

// ---------------------------------------------------------------------------
// WMO weather code helpers
// ---------------------------------------------------------------------------

enum WeatherCondition {
  clear,
  partlyCloudy,
  overcast,
  fog,
  drizzle,
  rain,
  snowShowers,
  thunderstorm,
}

WeatherCondition conditionFromCode(int code) {
  if (code == 0) return WeatherCondition.clear;
  if (code <= 2) return WeatherCondition.partlyCloudy;
  if (code == 3) return WeatherCondition.overcast;
  if (code == 45 || code == 48) return WeatherCondition.fog;
  if (code >= 51 && code <= 57) return WeatherCondition.drizzle;
  if ((code >= 61 && code <= 67) || (code >= 80 && code <= 82)) {
    return WeatherCondition.rain;
  }
  if ((code >= 71 && code <= 77) || code == 85 || code == 86) {
    return WeatherCondition.snowShowers;
  }
  if (code >= 95) return WeatherCondition.thunderstorm;
  return WeatherCondition.partlyCloudy;
}

String descriptionForCode(int code) {
  if (code == 0) return '晴朗';
  if (code == 1) return '基本晴朗';
  if (code == 2) return '局部多云';
  if (code == 3) return '多云';
  if (code == 45 || code == 48) return '有雾';
  if (code >= 51 && code <= 55) return '毛毛雨';
  if (code >= 56 && code <= 57) return '冻雨';
  if (code >= 61 && code <= 63) return '小雨';
  if (code >= 64 && code <= 65) return '中到大雨';
  if (code >= 66 && code <= 67) return '冻雨';
  if (code >= 71 && code <= 77) return '降雪';
  if (code >= 80 && code <= 82) return '阵雨';
  if (code == 85 || code == 86) return '阵雪';
  if (code == 95) return '雷阵雨';
  if (code == 96 || code == 99) return '强雷暴';
  return '未知';
}

IconData iconForCode(int code) {
  if (code == 0) return Icons.wb_sunny_rounded;
  if (code <= 2) return Icons.wb_cloudy_rounded;
  if (code == 3) return Icons.cloud_rounded;
  if (code == 45 || code == 48) return Icons.foggy;
  if (code >= 51 && code <= 57) return Icons.grain_rounded;
  if (code >= 61 && code <= 67) return Icons.umbrella_rounded;
  if (code >= 71 && code <= 86) return Icons.ac_unit_rounded;
  if (code >= 80 && code <= 82) return Icons.thunderstorm_rounded;
  if (code >= 95) return Icons.electric_bolt_rounded;
  return Icons.wb_cloudy_rounded;
}

String windDirectionLabel(int deg) {
  const dirs = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
  return dirs[((deg + 22.5) / 45).floor() % 8];
}

// ---------------------------------------------------------------------------
// Sky theme — gradient + particle type for background
// ---------------------------------------------------------------------------

class WeatherSkyTheme {
  final List<Color> gradientColors;
  final Color primaryColor;
  /// 'aurora' | 'stars' | 'clouds' | 'rain' | 'snow' | 'fog'
  final String particleType;

  const WeatherSkyTheme({
    required this.gradientColors,
    required this.primaryColor,
    this.particleType = 'none',
  });
}

enum _TimeOfDay { night, sunrise, day, sunset }

_TimeOfDay _tod(int hour) {
  if (hour >= 5 && hour < 8) return _TimeOfDay.sunrise;
  if (hour >= 8 && hour < 17) return _TimeOfDay.day;
  if (hour >= 17 && hour < 20) return _TimeOfDay.sunset;
  return _TimeOfDay.night;
}

WeatherSkyTheme weatherSkyThemeFor({
  required WeatherCondition condition,
  required DateTime now,
}) {
  final tod = _tod(now.hour);

  switch (condition) {
    case WeatherCondition.clear:
      switch (tod) {
        case _TimeOfDay.night:
          return const WeatherSkyTheme(
            gradientColors: [Color(0xFF0B1426), Color(0xFF1A2D50), Color(0xFF0D1E35)],
            primaryColor: Color(0xFF5E7CB8),
            particleType: 'stars',
          );
        case _TimeOfDay.sunrise:
          return const WeatherSkyTheme(
            gradientColors: [Color(0xFFFF7043), Color(0xFFFFB300), Color(0xFF64B5F6), Color(0xFF1976D2)],
            primaryColor: Color(0xFFFF7043),
            particleType: 'none',
          );
        case _TimeOfDay.day:
          return const WeatherSkyTheme(
            gradientColors: [Color(0xFF2196F3), Color(0xFF42A5F5), Color(0xFF64B5F6)],
            primaryColor: Color(0xFF42A5F5),
            particleType: 'clouds',
          );
        case _TimeOfDay.sunset:
          return const WeatherSkyTheme(
            gradientColors: [Color(0xFFFF5252), Color(0xFFFF9800), Color(0xFF9C27B0), Color(0xFF1A237E)],
            primaryColor: Color(0xFFFF7043),
            particleType: 'none',
          );
      }

    case WeatherCondition.partlyCloudy:
      switch (tod) {
        case _TimeOfDay.night:
          return const WeatherSkyTheme(
            gradientColors: [Color(0xFF1A2332), Color(0xFF263547), Color(0xFF1E3250)],
            primaryColor: Color(0xFF4A6FA5),
            particleType: 'stars',
          );
        case _TimeOfDay.sunrise || _TimeOfDay.sunset:
          return const WeatherSkyTheme(
            gradientColors: [Color(0xFFFF6F00), Color(0xFFFFCA28), Color(0xFF5C6BC0)],
            primaryColor: Color(0xFFFFB347),
            particleType: 'clouds',
          );
        case _TimeOfDay.day:
          return const WeatherSkyTheme(
            gradientColors: [Color(0xFF3D87C8), Color(0xFF6AB0D8), Color(0xFF89B4DA)],
            primaryColor: Color(0xFF5B9BD5),
            particleType: 'clouds',
          );
      }

    case WeatherCondition.overcast:
      if (tod == _TimeOfDay.night) {
        return const WeatherSkyTheme(
          gradientColors: [Color(0xFF1A1F2E), Color(0xFF2D3448), Color(0xFF1E2535)],
          primaryColor: Color(0xFF3A4560),
          particleType: 'none',
        );
      }
      return const WeatherSkyTheme(
        gradientColors: [Color(0xFF455A64), Color(0xFF607D8B), Color(0xFF78909C)],
        primaryColor: Color(0xFF607D8B),
        particleType: 'clouds',
      );

    case WeatherCondition.fog:
      return const WeatherSkyTheme(
        gradientColors: [Color(0xFF6E7E8A), Color(0xFFB0C4CE), Color(0xFFCFD9DF)],
        primaryColor: Color(0xFFB0C4CE),
        particleType: 'fog',
      );

    case WeatherCondition.drizzle:
      if (tod == _TimeOfDay.night) {
        return const WeatherSkyTheme(
          gradientColors: [Color(0xFF0F1B2E), Color(0xFF1A2A40), Color(0xFF1E3250)],
          primaryColor: Color(0xFF2E5688),
          particleType: 'rain',
        );
      }
      return const WeatherSkyTheme(
        gradientColors: [Color(0xFF2C3E6A), Color(0xFF3A5280), Color(0xFF4A6898)],
        primaryColor: Color(0xFF4A6898),
        particleType: 'rain',
      );

    case WeatherCondition.rain:
      if (tod == _TimeOfDay.night) {
        return const WeatherSkyTheme(
          gradientColors: [Color(0xFF0A1020), Color(0xFF111D30), Color(0xFF162340)],
          primaryColor: Color(0xFF1E3A5F),
          particleType: 'rain',
        );
      }
      return const WeatherSkyTheme(
        gradientColors: [Color(0xFF1E3A5F), Color(0xFF2980B9), Color(0xFF3D7FC5)],
        primaryColor: Color(0xFF2980B9),
        particleType: 'rain',
      );

    case WeatherCondition.snowShowers:
      return const WeatherSkyTheme(
        gradientColors: [Color(0xFF7B97B5), Color(0xFFC9D8E8), Color(0xFFE8F0F7)],
        primaryColor: Color(0xFF8FA8C8),
        particleType: 'snow',
      );

    case WeatherCondition.thunderstorm:
      return const WeatherSkyTheme(
        gradientColors: [Color(0xFF0D0D1A), Color(0xFF1A1A2E), Color(0xFF16213E)],
        primaryColor: Color(0xFF4A4AFF),
        particleType: 'rain',
      );
  }
}

// ---------------------------------------------------------------------------
// Static particle seed data (fixed so particles don't jump on rebuild)
// ---------------------------------------------------------------------------

class _ParticleSeeds {
  static final _rng = math.Random(42);

  static final stars = List.generate(
    70,
    (_) => Offset(_rng.nextDouble(), _rng.nextDouble() * 0.8),
  );
  static final starSizes = List.generate(70, (_) => _rng.nextDouble() * 1.4 + 0.5);
  static final starTwinklePhase = List.generate(70, (_) => _rng.nextDouble() * math.pi * 2);

  static final clouds = List.generate(
    6,
    (i) => Offset(i / 6.0, 0.04 + _rng.nextDouble() * 0.4),
  );
  static final cloudSizes = List.generate(6, (_) => 0.15 + _rng.nextDouble() * 0.12);
  static final cloudSpeeds = List.generate(6, (_) => 0.04 + _rng.nextDouble() * 0.08);

  static final rainDrops = List.generate(
    90,
    (_) => Offset(_rng.nextDouble(), _rng.nextDouble()),
  );
  static final rainSpeeds = List.generate(90, (_) => 0.6 + _rng.nextDouble() * 0.8);

  static final snowFlakes = List.generate(
    55,
    (_) => Offset(_rng.nextDouble(), _rng.nextDouble()),
  );
  static final snowSizes = List.generate(55, (_) => 1.5 + _rng.nextDouble() * 2.5);
  static final snowDrift = List.generate(55, (_) => (_rng.nextDouble() - 0.5) * 0.04);
  static final snowSpeeds = List.generate(55, (_) => 0.08 + _rng.nextDouble() * 0.1);
}

/// CustomPainter used by WeatherBackground.
class SkyParticlePainter extends CustomPainter {
  final String particleType;
  final double t;
  final Color primaryColor;

  const SkyParticlePainter({
    required this.particleType,
    required this.t,
    required this.primaryColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    switch (particleType) {
      case 'stars':
        _paintStars(canvas, size);
      case 'clouds':
        _paintClouds(canvas, size);
      case 'rain':
        _paintRain(canvas, size);
      case 'snow':
        _paintSnow(canvas, size);
      case 'fog':
        _paintFog(canvas, size);
      case 'aurora':
        _paintAurora(canvas, size);
    }
  }

  void _paintStars(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final seeds = _ParticleSeeds.stars;
    for (int i = 0; i < seeds.length; i++) {
      final twinkle = math.sin(t * math.pi * 2 + _ParticleSeeds.starTwinklePhase[i]);
      final alpha = 0.3 + 0.55 * (twinkle * 0.5 + 0.5);
      paint.color = Colors.white.withOpacity(alpha);
      canvas.drawCircle(
        Offset(seeds[i].dx * size.width, seeds[i].dy * size.height),
        _ParticleSeeds.starSizes[i],
        paint,
      );
    }
  }

  void _paintClouds(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final clouds = _ParticleSeeds.clouds;
    for (int i = 0; i < clouds.length; i++) {
      final x = ((clouds[i].dx + t * _ParticleSeeds.cloudSpeeds[i]) % 1.2 - 0.1);
      final y = clouds[i].dy;
      final r = _ParticleSeeds.cloudSizes[i] * size.width;
      paint.color = Colors.white.withOpacity(0.04 + i * 0.015);
      // Fluffy cloud using three overlapping ovals
      canvas.drawOval(Rect.fromCenter(
          center: Offset(x * size.width, y * size.height),
          width: r * 2.4,
          height: r * 0.9), paint);
      canvas.drawOval(Rect.fromCenter(
          center: Offset(x * size.width - r * 0.5, y * size.height - r * 0.2),
          width: r * 1.5,
          height: r * 0.9), paint);
      canvas.drawOval(Rect.fromCenter(
          center: Offset(x * size.width + r * 0.5, y * size.height - r * 0.15),
          width: r * 1.3,
          height: r * 0.75), paint);
    }
  }

  void _paintRain(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    for (int i = 0; i < _ParticleSeeds.rainDrops.length; i++) {
      final speed = _ParticleSeeds.rainSpeeds[i];
      final y = ((_ParticleSeeds.rainDrops[i].dy + t * speed) % 1.0) * size.height;
      final x = _ParticleSeeds.rainDrops[i].dx * size.width + t * 20;
      paint.color = const Color(0xFF90CAF9).withOpacity(0.22 + speed * 0.08);
      canvas.drawLine(
        Offset(x - 2, y - 14),
        Offset(x + 2, y),
        paint,
      );
    }
  }

  void _paintSnow(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (int i = 0; i < _ParticleSeeds.snowFlakes.length; i++) {
      final speed = _ParticleSeeds.snowSpeeds[i];
      final drift = _ParticleSeeds.snowDrift[i];
      final y = ((_ParticleSeeds.snowFlakes[i].dy + t * speed) % 1.0) * size.height;
      final x = (_ParticleSeeds.snowFlakes[i].dx + t * drift) * size.width;
      paint.color = Colors.white.withOpacity(0.5 + speed * 0.3);
      canvas.drawCircle(
        Offset(x, y),
        _ParticleSeeds.snowSizes[i],
        paint,
      );
    }
  }

  void _paintFog(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (int i = 0; i < 4; i++) {
      final x = ((i / 4.0 + t * 0.03) % 1.1 - 0.1) * size.width;
      final y = size.height * (0.2 + i * 0.18);
      final w = size.width * (0.8 + i * 0.1);
      paint.color = Colors.white.withOpacity(0.06 + i * 0.02);
      canvas.drawOval(Rect.fromCenter(
          center: Offset(x + w / 2, y), width: w, height: 60), paint);
    }
  }

  void _paintAurora(Canvas canvas, Size size) {
    // Subtle aurora blobs — fallback when no weather data
    final blobs = [
      (color: const Color(0xFF00D9FF), opacity: 0.07, cx: 0.15, cy: 0.0, r: 0.55),
      (color: const Color(0xFF0A84FF), opacity: 0.06, cx: 0.85, cy: 0.1, r: 0.38),
      (color: const Color(0xFF00B4A0), opacity: 0.05, cx: 0.9, cy: 0.75, r: 0.45),
      (color: const Color(0xFF5E5CE6), opacity: 0.04, cx: 0.1, cy: 0.8, r: 0.32),
    ];
    final drift = math.sin(t * math.pi * 2) * 0.02;
    for (final b in blobs) {
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [b.color.withOpacity(b.opacity + drift.abs()), Colors.transparent],
        ).createShader(Rect.fromCircle(
          center: Offset((b.cx + drift) * size.width, b.cy * size.height),
          radius: b.r * size.width,
        ));
      canvas.drawCircle(
        Offset((b.cx + drift) * size.width, b.cy * size.height),
        b.r * size.width,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(SkyParticlePainter old) =>
      old.t != t || old.particleType != particleType;
}

// ---------------------------------------------------------------------------
// WeatherState
// ---------------------------------------------------------------------------

class WeatherState {
  final double? temperature;    // °C
  final double? feelsLike;      // °C
  final int? weatherCode;       // WMO
  final WeatherCondition? condition;
  final double? windSpeed;      // knots
  final int? windDirection;     // degrees true
  final double? precipitation;  // mm
  final String? description;
  final DateTime? fetchedAt;
  final bool isLoading;
  final String? error;
  /// Location label used for display (e.g. "Auckland", or lat/lon)
  final String? locationLabel;

  const WeatherState({
    this.temperature,
    this.feelsLike,
    this.weatherCode,
    this.condition,
    this.windSpeed,
    this.windDirection,
    this.precipitation,
    this.description,
    this.fetchedAt,
    this.isLoading = false,
    this.error,
    this.locationLabel,
  });

  const WeatherState.loading() : this(isLoading: true);
  const WeatherState.empty() : this();

  /// Returns the sky theme for this weather + current time of day.
  WeatherSkyTheme skyTheme(DateTime now) {
    if (condition == null) {
      return const WeatherSkyTheme(
        gradientColors: [Color(0xFF020D1B), Color(0xFF071525), Color(0xFF010810)],
        primaryColor: Color(0xFF00D9FF),
        particleType: 'aurora',
      );
    }
    return weatherSkyThemeFor(condition: condition!, now: now);
  }

  WeatherState copyWith({
    double? temperature,
    double? feelsLike,
    int? weatherCode,
    WeatherCondition? condition,
    double? windSpeed,
    int? windDirection,
    double? precipitation,
    String? description,
    DateTime? fetchedAt,
    bool? isLoading,
    String? error,
    String? locationLabel,
  }) =>
      WeatherState(
        temperature: temperature ?? this.temperature,
        feelsLike: feelsLike ?? this.feelsLike,
        weatherCode: weatherCode ?? this.weatherCode,
        condition: condition ?? this.condition,
        windSpeed: windSpeed ?? this.windSpeed,
        windDirection: windDirection ?? this.windDirection,
        precipitation: precipitation ?? this.precipitation,
        description: description ?? this.description,
        fetchedAt: fetchedAt ?? this.fetchedAt,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        locationLabel: locationLabel ?? this.locationLabel,
      );
}
