import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/weather_state.dart';
import '../../../core/providers/weather_provider.dart';

// ---------------------------------------------------------------------------
// WeatherBackground — iOS Weather-style animated sky behind the home screen
// ---------------------------------------------------------------------------

class WeatherBackground extends ConsumerStatefulWidget {
  const WeatherBackground({super.key});

  @override
  ConsumerState<WeatherBackground> createState() => _WeatherBackgroundState();
}

class _WeatherBackgroundState extends ConsumerState<WeatherBackground>
    with TickerProviderStateMixin {
  // Slow loop for clouds, stars, snow, aurora (40s cycle)
  late final AnimationController _slowCtrl;
  // Fast loop for rain (2s cycle)
  late final AnimationController _fastCtrl;

  // Track the previous gradient for cross-fade transition
  WeatherSkyTheme _prev = const WeatherSkyTheme(
    gradientColors: [Color(0xFF020D1B), Color(0xFF07111F), Color(0xFF010810)],
    primaryColor: Color(0xFF00D9FF),
    particleType: 'aurora',
  );
  WeatherSkyTheme _curr = const WeatherSkyTheme(
    gradientColors: [Color(0xFF020D1B), Color(0xFF07111F), Color(0xFF010810)],
    primaryColor: Color(0xFF00D9FF),
    particleType: 'aurora',
  );
  // Key forces TweenAnimationBuilder restart on theme change
  int _themeKey = 0;

  @override
  void initState() {
    super.initState();
    _slowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 40),
    )..repeat();
    _fastCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _slowCtrl.dispose();
    _fastCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final weather = ref.watch(weatherProvider);
    final newTheme = weather.skyTheme(DateTime.now());

    // Detect theme change and trigger cross-fade
    if (newTheme.gradientColors.first.value != _curr.gradientColors.first.value) {
      _prev = _curr;
      _curr = newTheme;
      _themeKey++;
    }

    final isRain = _curr.particleType == 'rain';

    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Gradient cross-fade ──────────────────────────────────────────────
        TweenAnimationBuilder<double>(
          key: ValueKey(_themeKey),
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(seconds: 3),
          curve: Curves.easeInOut,
          builder: (_, t, __) {
            final colors = _lerpGradientColors(_prev.gradientColors, _curr.gradientColors, t);
            return Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: colors,
                ),
              ),
            );
          },
        ),

        // ── Particle layer ───────────────────────────────────────────────────
        Positioned.fill(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: isRain ? _fastCtrl : _slowCtrl,
              builder: (_, __) => CustomPaint(
                painter: SkyParticlePainter(
                  particleType: _curr.particleType,
                  t: isRain ? _fastCtrl.value : _slowCtrl.value,
                  primaryColor: _curr.primaryColor,
                  now: DateTime.now(),
                ),
              ),
            ),
          ),
        ),

        // ── Readability overlay — vignette edges for UI legibility ───────────
        const Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x55000000), // top darkening for header
                    Colors.transparent,
                    Colors.transparent,
                    Color(0x66000000), // bottom darkening for status bar
                  ],
                  stops: [0.0, 0.25, 0.70, 1.0],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Lerp between two gradient color lists, padding the shorter with its last color.
List<Color> _lerpGradientColors(List<Color> a, List<Color> b, double t) {
  final len = math.max(a.length, b.length);
  return List.generate(len, (i) {
    final ca = i < a.length ? a[i] : a.last;
    final cb = i < b.length ? b[i] : b.last;
    return Color.lerp(ca, cb, t)!;
  });
}
