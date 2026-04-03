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

// 8 time bands for smooth realistic sky progression
enum _TimeOfDay { deepNight, preDawn, dawn, morning, midday, afternoon, goldenHour, dusk }

_TimeOfDay _tod(int hour) {
  if (hour >= 22 || hour < 4) return _TimeOfDay.deepNight;
  if (hour < 5) return _TimeOfDay.preDawn;
  if (hour < 7) return _TimeOfDay.dawn;
  if (hour < 10) return _TimeOfDay.morning;
  if (hour < 16) return _TimeOfDay.midday;
  if (hour < 18) return _TimeOfDay.afternoon;
  if (hour < 19) return _TimeOfDay.goldenHour;
  return _TimeOfDay.dusk;
}

WeatherSkyTheme weatherSkyThemeFor({
  required WeatherCondition condition,
  required DateTime now,
}) {
  final tod = _tod(now.hour);

  switch (condition) {
    case WeatherCondition.clear:
      switch (tod) {
        case _TimeOfDay.deepNight:
          return const WeatherSkyTheme(
            gradientColors: [Color(0xFF040A16), Color(0xFF0A1528), Color(0xFF06101E)],
            primaryColor: Color(0xFF4A6FA5),
            particleType: 'stars',
          );
        case _TimeOfDay.preDawn:
          return const WeatherSkyTheme(
            gradientColors: [Color(0xFF080C28), Color(0xFF14103A), Color(0xFF200E30)],
            primaryColor: Color(0xFF6A5CC0),
            particleType: 'stars',
          );
        case _TimeOfDay.dawn:
          return const WeatherSkyTheme(
            gradientColors: [Color(0xFF0E0C35), Color(0xFF5C2280), Color(0xFFD45820), Color(0xFFFFCC80)],
            primaryColor: Color(0xFFE87040),
            particleType: 'none',
          );
        case _TimeOfDay.morning:
          return const WeatherSkyTheme(
            gradientColors: [Color(0xFF0B50C0), Color(0xFF1A8AE8), Color(0xFF78C8F5), Color(0xFFEED8B0)],
            primaryColor: Color(0xFF2090E0),
            particleType: 'clouds',
          );
        case _TimeOfDay.midday:
          return const WeatherSkyTheme(
            gradientColors: [Color(0xFF0840A8), Color(0xFF1068C8), Color(0xFF40A8E8), Color(0xFF80C8F0)],
            primaryColor: Color(0xFF1878D0),
            particleType: 'clouds',
          );
        case _TimeOfDay.afternoon:
          return const WeatherSkyTheme(
            gradientColors: [Color(0xFF083898), Color(0xFF1560C0), Color(0xFF3C90D5), Color(0xFFA8D5F0)],
            primaryColor: Color(0xFF1565C0),
            particleType: 'clouds',
          );
        case _TimeOfDay.goldenHour:
          return const WeatherSkyTheme(
            gradientColors: [Color(0xFF100630), Color(0xFF601880), Color(0xFFD05818), Color(0xFFFFD060)],
            primaryColor: Color(0xFFE06820),
            particleType: 'none',
          );
        case _TimeOfDay.dusk:
          return const WeatherSkyTheme(
            gradientColors: [Color(0xFF06081E), Color(0xFF1A0C38), Color(0xFF340A50), Color(0xFF1A1028)],
            primaryColor: Color(0xFF7040A0),
            particleType: 'stars',
          );
      }

    case WeatherCondition.partlyCloudy:
      switch (tod) {
        case _TimeOfDay.deepNight || _TimeOfDay.preDawn:
          return const WeatherSkyTheme(
            gradientColors: [Color(0xFF080E20), Color(0xFF111C30), Color(0xFF0C1828)],
            primaryColor: Color(0xFF3A5888),
            particleType: 'stars',
          );
        case _TimeOfDay.dawn:
          return const WeatherSkyTheme(
            gradientColors: [Color(0xFF181040), Color(0xFF703890), Color(0xFFCC6030), Color(0xFFEEAA60)],
            primaryColor: Color(0xFFCC6838),
            particleType: 'clouds',
          );
        case _TimeOfDay.morning:
          return const WeatherSkyTheme(
            gradientColors: [Color(0xFF1860B8), Color(0xFF3098D8), Color(0xFF80C0E8), Color(0xFFD8E8F5)],
            primaryColor: Color(0xFF3898D0),
            particleType: 'clouds',
          );
        case _TimeOfDay.midday || _TimeOfDay.afternoon:
          return const WeatherSkyTheme(
            gradientColors: [Color(0xFF1050A0), Color(0xFF2878C0), Color(0xFF5AA0D8), Color(0xFF90C0E8)],
            primaryColor: Color(0xFF3080C0),
            particleType: 'clouds',
          );
        case _TimeOfDay.goldenHour || _TimeOfDay.dusk:
          return const WeatherSkyTheme(
            gradientColors: [Color(0xFF180838), Color(0xFF683080), Color(0xFFB84820), Color(0xFFEEA840)],
            primaryColor: Color(0xFFC05030),
            particleType: 'clouds',
          );
      }

    case WeatherCondition.overcast:
      switch (tod) {
        case _TimeOfDay.deepNight || _TimeOfDay.preDawn:
          return const WeatherSkyTheme(
            gradientColors: [Color(0xFF0C1018), Color(0xFF181E28), Color(0xFF101820)],
            primaryColor: Color(0xFF283848),
            particleType: 'none',
          );
        case _TimeOfDay.dawn || _TimeOfDay.dusk:
          return const WeatherSkyTheme(
            gradientColors: [Color(0xFF281820), Color(0xFF403040), Color(0xFF504050)],
            primaryColor: Color(0xFF604858),
            particleType: 'none',
          );
        default:
          return const WeatherSkyTheme(
            gradientColors: [Color(0xFF384048), Color(0xFF505860), Color(0xFF686870)],
            primaryColor: Color(0xFF607080),
            particleType: 'clouds',
          );
      }

    case WeatherCondition.fog:
      return const WeatherSkyTheme(
        gradientColors: [Color(0xFF586068), Color(0xFF8898A0), Color(0xFFC0CCCC), Color(0xFFD8E0DC)],
        primaryColor: Color(0xFF98B0B0),
        particleType: 'fog',
      );

    case WeatherCondition.drizzle:
      switch (tod) {
        case _TimeOfDay.deepNight || _TimeOfDay.preDawn:
          return const WeatherSkyTheme(
            gradientColors: [Color(0xFF081018), Color(0xFF101C28), Color(0xFF0C1820)],
            primaryColor: Color(0xFF204060),
            particleType: 'rain',
          );
        default:
          return const WeatherSkyTheme(
            gradientColors: [Color(0xFF203060), Color(0xFF304870), Color(0xFF405880)],
            primaryColor: Color(0xFF406090),
            particleType: 'rain',
          );
      }

    case WeatherCondition.rain:
      switch (tod) {
        case _TimeOfDay.deepNight || _TimeOfDay.preDawn:
          return const WeatherSkyTheme(
            gradientColors: [Color(0xFF060A14), Color(0xFF0C1428), Color(0xFF101A30)],
            primaryColor: Color(0xFF182A48),
            particleType: 'rain',
          );
        default:
          return const WeatherSkyTheme(
            gradientColors: [Color(0xFF1A2A50), Color(0xFF243860), Color(0xFF3060A0)],
            primaryColor: Color(0xFF2878B0),
            particleType: 'rain',
          );
      }

    case WeatherCondition.snowShowers:
      return const WeatherSkyTheme(
        gradientColors: [Color(0xFF6878A0), Color(0xFF9CB0CC), Color(0xFFC8D8E8), Color(0xFFE0ECF4)],
        primaryColor: Color(0xFF80A0C0),
        particleType: 'snow',
      );

    case WeatherCondition.thunderstorm:
      return const WeatherSkyTheme(
        gradientColors: [Color(0xFF080810), Color(0xFF100C20), Color(0xFF0C1020)],
        primaryColor: Color(0xFF3030A0),
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
  /// Current time — used to position sun and moon accurately.
  final DateTime? now;

  const SkyParticlePainter({
    required this.particleType,
    required this.t,
    required this.primaryColor,
    this.now,
  });

  @override
  void paint(Canvas canvas, Size size) {
    switch (particleType) {
      case 'stars':
        _paintStars(canvas, size);
        _paintMoon(canvas, size);
      case 'clouds':
        _paintClouds(canvas, size);
        _paintSun(canvas, size);
      case 'rain':
        _paintRain(canvas, size);
      case 'snow':
        _paintSnow(canvas, size);
      case 'fog':
        _paintFog(canvas, size);
      case 'aurora':
        _paintAurora(canvas, size);
      case 'none':
        // dawn / dusk — paint celestial body only
        _paintSunOrMoon(canvas, size);
    }
  }

  void _paintSunOrMoon(Canvas canvas, Size size) {
    final hour = _fractionalHour();
    if (hour >= 5.0 && hour <= 20.5) {
      _paintSun(canvas, size);
    } else {
      _paintMoon(canvas, size);
    }
  }

  double _fractionalHour() {
    if (now == null) return 12.0;
    return now!.hour + now!.minute / 60.0;
  }

  void _paintSun(Canvas canvas, Size size) {
    final hour = _fractionalHour();
    if (hour < 5.0 || hour > 20.5) return;

    // Arc: rises east side (x=0.82) at 6am, zenith at noon (x=0.50, y=0.10),
    // sets west side (x=0.18) at 18:30.
    final progress = ((hour - 5.5) / 15.0).clamp(0.0, 1.0);
    final altitude = math.sin(progress * math.pi); // 0..1
    final sunX = 0.82 - 0.64 * progress;
    final sunY = 0.90 - 0.80 * altitude;

    final cx = sunX * size.width;
    final cy = sunY * size.height;

    // Atmospheric scatter — large diffuse halo
    final scatterColor = altitude > 0.35
        ? const Color(0xFFFFEA90)
        : const Color(0xFFFF9040);
    final scatterOpacity = (0.10 + 0.18 * altitude).clamp(0.0, 0.28);
    canvas.drawCircle(
      Offset(cx, cy),
      size.width * 0.28,
      Paint()
        ..shader = RadialGradient(
          colors: [scatterColor.withOpacity(scatterOpacity), Colors.transparent],
          stops: const [0.0, 1.0],
        ).createShader(Rect.fromCircle(
            center: Offset(cx, cy), radius: size.width * 0.28)),
    );

    // Corona glow
    final diskR = 10.0 + 10.0 * altitude;
    canvas.drawCircle(
      Offset(cx, cy),
      diskR + 20,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.white.withOpacity(0.40), Colors.transparent],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: diskR + 20)),
    );

    // Sun disk
    canvas.drawCircle(
      Offset(cx, cy),
      diskR,
      Paint()..color = Colors.white.withOpacity(0.95),
    );

    // Bright core
    canvas.drawCircle(
      Offset(cx, cy),
      diskR * 0.5,
      Paint()..color = Colors.white,
    );
  }

  void _paintMoon(Canvas canvas, Size size) {
    final hour = _fractionalHour();
    // Moon visible when sun is below horizon
    if (hour >= 5.5 && hour <= 20.0) return;

    final cx = size.width * 0.70;
    final cy = size.height * 0.15;

    // Soft glow
    canvas.drawCircle(
      Offset(cx, cy),
      55,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.white.withOpacity(0.09), Colors.transparent],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: 55)),
    );

    // Moon disk with crescent via saveLayer + clear blend
    final moonRect = Rect.fromCenter(center: Offset(cx, cy), width: 72, height: 72);
    canvas.saveLayer(moonRect, Paint());
    canvas.drawCircle(Offset(cx, cy), 16, Paint()..color = const Color(0xFFD8E4EE));
    canvas.drawCircle(
      Offset(cx + 10, cy - 5),
      13,
      Paint()
        ..color = Colors.white
        ..blendMode = BlendMode.clear,
    );
    canvas.restore();
  }

  void _paintStars(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final seeds = _ParticleSeeds.stars;
    for (int i = 0; i < seeds.length; i++) {
      final twinkle = math.sin(t * math.pi * 2 + _ParticleSeeds.starTwinklePhase[i]);
      final alpha = 0.25 + 0.65 * (twinkle * 0.5 + 0.5);
      final sz = _ParticleSeeds.starSizes[i];
      // Larger stars get a subtle glow
      if (sz > 1.4) {
        paint.color = Colors.white.withOpacity(alpha * 0.25);
        canvas.drawCircle(
          Offset(seeds[i].dx * size.width, seeds[i].dy * size.height),
          sz * 2.8,
          paint,
        );
      }
      paint.color = Colors.white.withOpacity(alpha);
      canvas.drawCircle(
        Offset(seeds[i].dx * size.width, seeds[i].dy * size.height),
        sz,
        paint,
      );
    }
  }

  void _paintClouds(Canvas canvas, Size size) {
    final seeds = _ParticleSeeds.clouds;
    for (int i = 0; i < seeds.length; i++) {
      final xFrac = (seeds[i].dx + t * _ParticleSeeds.cloudSpeeds[i]) % 1.25 - 0.12;
      final yFrac = seeds[i].dy;
      final r = _ParticleSeeds.cloudSizes[i] * size.width;
      final cx = xFrac * size.width;
      final cy = yFrac * size.height;
      final alpha = 0.09 + i * 0.025;

      void puff(double dx, double dy, double pr, double opMul) {
        canvas.drawCircle(
          Offset(cx + dx, cy + dy),
          pr,
          Paint()
            ..shader = RadialGradient(
              colors: [
                Colors.white.withOpacity(alpha * opMul),
                Colors.white.withOpacity(0),
              ],
              stops: const [0.25, 1.0],
            ).createShader(
                Rect.fromCircle(center: Offset(cx + dx, cy + dy), radius: pr)),
        );
      }

      puff(0, 0, r, 1.4);
      puff(-r * 0.65, r * 0.12, r * 0.72, 1.0);
      puff(r * 0.58, r * 0.08, r * 0.65, 1.0);
      puff(-r * 0.18, -r * 0.30, r * 0.58, 0.85);
      puff(r * 0.28, -r * 0.26, r * 0.52, 0.80);
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
    // Real aurora borealis: wavy horizontal light bands over a starry sky

    // Stars first
    _paintStars(canvas, size);

    // Aurora bands — each a wavy path with vertical gradient fade
    final bands = [
      (yFrac: 0.18, color: const Color(0xFF00E5CC), amp: 0.055, phase: 0.0,   width: 0.22, opacity: 0.18),
      (yFrac: 0.28, color: const Color(0xFF00AAFF), amp: 0.045, phase: 2.1,   width: 0.18, opacity: 0.14),
      (yFrac: 0.42, color: const Color(0xFF7B4FE0), amp: 0.035, phase: 1.1,   width: 0.14, opacity: 0.11),
      (yFrac: 0.12, color: const Color(0xFF00FFB0), amp: 0.030, phase: 3.5,   width: 0.10, opacity: 0.09),
    ];

    for (final b in bands) {
      final yBase = b.yFrac * size.height;
      final amplitude = b.amp * size.height;
      final bandH = b.width * size.height;

      final path = Path();
      const steps = 80;
      // Top wavy edge
      for (int i = 0; i <= steps; i++) {
        final xFrac = i / steps;
        final wave = amplitude *
            math.sin(xFrac * math.pi * 5 + t * math.pi * 2 + b.phase);
        final x = xFrac * size.width;
        final y = yBase + wave;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      // Bottom edge (offset down by bandH with slight inverse wave)
      for (int i = steps; i >= 0; i--) {
        final xFrac = i / steps;
        final wave = amplitude * 0.5 *
            math.sin(xFrac * math.pi * 5 + t * math.pi * 2 + b.phase + math.pi);
        path.lineTo(xFrac * size.width, yBase + bandH + wave);
      }
      path.close();

      // Vertical gradient: bright at top edge, transparent at bottom
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              b.color.withOpacity(b.opacity),
              b.color.withOpacity(b.opacity * 0.3),
              b.color.withOpacity(0),
            ],
            stops: const [0.0, 0.55, 1.0],
          ).createShader(Rect.fromLTWH(0, yBase - amplitude, size.width, bandH + amplitude * 2)),
      );
    }
  }

  @override
  bool shouldRepaint(SkyParticlePainter old) =>
      old.t != t || old.particleType != particleType || old.now?.minute != now?.minute;
}

// ---------------------------------------------------------------------------
// Tidal data model
// ---------------------------------------------------------------------------

class TideEntry {
  final DateTime time;
  final double height; // meters
  final bool isHighTide; // true = high tide, false = low tide
  const TideEntry({required this.time, required this.height, required this.isHighTide});
}

// ---------------------------------------------------------------------------
// Forecast data models
// ---------------------------------------------------------------------------

class HourlyForecast {
  final DateTime time;
  final double? temp;       // °C
  final double? windSpeed;  // knots (converted from m/s × 1.944)
  final int? windDir;       // degrees
  final double? windGust;   // knots
  final double? precip;     // mm/h
  final double? waveHeight; // m
  final double? wavePeriod; // s
  final double? pressure;   // hPa
  final String? symbolCode;

  const HourlyForecast({
    required this.time,
    this.temp,
    this.windSpeed,
    this.windDir,
    this.windGust,
    this.precip,
    this.waveHeight,
    this.wavePeriod,
    this.pressure,
    this.symbolCode,
  });
}

class DailyForecast {
  final DateTime date;
  final double? tempMax;
  final double? tempMin;
  final double? windSpeedMax; // knots
  final int? windDirDominant; // degrees
  final double? precipTotal;  // mm
  final double? waveHeightMax; // m
  final String? symbolCode;

  const DailyForecast({
    required this.date,
    this.tempMax,
    this.tempMin,
    this.windSpeedMax,
    this.windDirDominant,
    this.precipTotal,
    this.waveHeightMax,
    this.symbolCode,
  });
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
  final double? waveHeight;    // current, metres
  final double? wavePeriod;    // current, seconds
  final double? swellHeight;   // current, metres
  final int? swellDirection;   // current, degrees
  final double? windGust;      // current, knots
  final double? pressure;      // hPa
  final double? humidity;      // %
  final double? dewPoint;      // °C — derived from temp + humidity
  final double? pressureTrend; // hPa/3h — positive = rising, negative = falling
  final double? cloudCover;    // 0.0–1.0 fraction
  final List<HourlyForecast> hourly;
  final List<DailyForecast> daily;
  final List<TideEntry> tides;

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
    this.waveHeight,
    this.wavePeriod,
    this.swellHeight,
    this.swellDirection,
    this.windGust,
    this.pressure,
    this.humidity,
    this.dewPoint,
    this.pressureTrend,
    this.cloudCover,
    this.hourly = const [],
    this.daily = const [],
    this.tides = const [],
  });

  const WeatherState.loading() : this(isLoading: true);
  const WeatherState.empty() : this();

  /// Returns the sky theme for this weather + current time of day.
  WeatherSkyTheme skyTheme(DateTime now) {
    if (condition == null) {
      // No weather data yet: beautiful deep aurora night sky
      return const WeatherSkyTheme(
        gradientColors: [Color(0xFF020810), Color(0xFF050D1E), Color(0xFF030A18), Color(0xFF020710)],
        primaryColor: Color(0xFF00E5CC),
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
    double? waveHeight,
    double? wavePeriod,
    double? swellHeight,
    int? swellDirection,
    double? windGust,
    double? pressure,
    double? humidity,
    double? dewPoint,
    double? pressureTrend,
    double? cloudCover,
    List<HourlyForecast>? hourly,
    List<DailyForecast>? daily,
    List<TideEntry>? tides,
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
        waveHeight: waveHeight ?? this.waveHeight,
        wavePeriod: wavePeriod ?? this.wavePeriod,
        swellHeight: swellHeight ?? this.swellHeight,
        swellDirection: swellDirection ?? this.swellDirection,
        windGust: windGust ?? this.windGust,
        pressure: pressure ?? this.pressure,
        humidity: humidity ?? this.humidity,
        dewPoint: dewPoint ?? this.dewPoint,
        pressureTrend: pressureTrend ?? this.pressureTrend,
        cloudCover: cloudCover ?? this.cloudCover,
        hourly: hourly ?? this.hourly,
        daily: daily ?? this.daily,
        tides: tides ?? this.tides,
      );
}
