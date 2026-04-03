import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/models/weather_state.dart';

// ---------------------------------------------------------------------------
// Public entry-point
// ---------------------------------------------------------------------------

/// Zoomable regional wind map (Windy/PredictWind style).
///
/// Shows animated wind particles flowing across the geographic area covered by
/// [windGrid].  A vessel marker is drawn at [vesselLat]/[vesselLon] when
/// provided.  Supports full multi-touch zoom/pan via [FlutterMap].
class WindMapWidget extends StatelessWidget {
  final List<WindGridPoint> windGrid;
  final double centerLat;
  final double centerLon;
  final double? vesselLat;
  final double? vesselLon;

  const WindMapWidget({
    super.key,
    required this.windGrid,
    required this.centerLat,
    required this.centerLon,
    this.vesselLat,
    this.vesselLon,
  });

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      options: MapOptions(
        initialCenter: LatLng(centerLat, centerLon),
        initialZoom: 7.0,
        minZoom: 4.0,
        maxZoom: 12.0,
      ),
      children: [
        // Dark-matter base tiles (CartoDB) — high contrast for coloured particles
        TileLayer(
          urlTemplate:
              'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
          subdomains: const ['a', 'b', 'c', 'd'],
          retinaMode: true,
          userAgentPackageName: 'com.yokuli.app',
        ),
        // Animated wind particles
        _WindParticleLayer(windGrid: windGrid),
        // Wind arrows at each grid point
        MarkerLayer(
          markers: windGrid
              .where((p) => p.windSpeed != null && p.windDir != null)
              .map((p) => Marker(
                    point: LatLng(p.lat, p.lon),
                    width: 18,
                    height: 18,
                    child: Transform.rotate(
                      angle: (p.windDir! + 180) * math.pi / 180.0,
                      child: Icon(
                        Icons.arrow_upward_rounded,
                        size: 12,
                        color: _bftColor(p.windSpeed!).withOpacity(0.65),
                      ),
                    ),
                  ))
              .toList(),
        ),
        // Vessel position
        if (vesselLat != null && vesselLon != null)
          MarkerLayer(
            markers: [
              Marker(
                point: LatLng(vesselLat!, vesselLon!),
                width: 28,
                height: 28,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.cyanAccent.withOpacity(0.2),
                    border: Border.all(color: Colors.cyanAccent, width: 1.5),
                  ),
                  child: const Icon(
                    Icons.navigation_rounded,
                    color: Colors.cyanAccent,
                    size: 14,
                  ),
                ),
              ),
            ],
          ),
        // Attribution
        RichAttributionWidget(
          attributions: [
            TextSourceAttribution('© OpenStreetMap contributors'),
            TextSourceAttribution('© CARTO'),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Animated particle layer — lives inside FlutterMap's children
// ---------------------------------------------------------------------------

class _WindParticleLayer extends StatefulWidget {
  final List<WindGridPoint> windGrid;
  const _WindParticleLayer({required this.windGrid});

  @override
  State<_WindParticleLayer> createState() => _WindParticleLayerState();
}

class _WindParticleLayerState extends State<_WindParticleLayer>
    with TickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _prev = Duration.zero;
  List<_Particle> _particles = [];

  static const _count     = 180;
  /// knots → deg/s, then multiplied by _vizMult for visual speed.
  /// Tuned so 20-kn wind gives ~30 px/s at zoom-7.
  static const _vizMult   = 3500.0;
  static const _kn2DegSec = 1.0 / (3600.0 * 60.0); // 1 kn ≈ 4.63e-6 °/s

  @override
  void initState() {
    super.initState();
    _buildParticles();
    _ticker = createTicker(_tick)..start();
  }

  @override
  void didUpdateWidget(_WindParticleLayer old) {
    super.didUpdateWidget(old);
    if (old.windGrid != widget.windGrid) _buildParticles();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _buildParticles() {
    if (widget.windGrid.isEmpty) { _particles = []; return; }
    final lats  = widget.windGrid.map((p) => p.lat);
    final lons  = widget.windGrid.map((p) => p.lon);
    final minLt = lats.reduce(math.min);
    final maxLt = lats.reduce(math.max);
    final minLn = lons.reduce(math.min);
    final maxLn = lons.reduce(math.max);
    final rng   = math.Random(1337);
    _particles  = List.generate(_count, (_) => _Particle(
      lat: minLt + rng.nextDouble() * (maxLt - minLt),
      lon: minLn + rng.nextDouble() * (maxLn - minLn),
      maxAge: 8 + rng.nextDouble() * 14,
      alpha:  0.45 + rng.nextDouble() * 0.55,
      minLt: minLt, maxLt: maxLt, minLn: minLn, maxLn: maxLn,
    ));
  }

  void _tick(Duration elapsed) {
    if (!mounted) return;
    final dt = ((elapsed - _prev).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _prev = elapsed;
    if (widget.windGrid.isEmpty) return;

    final rng = math.Random();
    for (final p in _particles) {
      p.prevLat = p.lat;
      p.prevLon = p.lon;

      // Nearest-neighbour wind interpolation
      WindGridPoint? near;
      var bestD = double.infinity;
      for (final g in widget.windGrid) {
        final d = (g.lat - p.lat) * (g.lat - p.lat)
                + (g.lon - p.lon) * (g.lon - p.lon);
        if (d < bestD) { bestD = d; near = g; }
      }

      if (near != null && near.windSpeed != null && near.windDir != null) {
        final spd = near.windSpeed!;
        final rad = near.windDir! * math.pi / 180.0;
        final cosLat = math.cos(p.lat * math.pi / 180.0).clamp(0.05, 1.0);
        // FROM dir → particle flows TO (dir+180°):
        // dLat = -cos(dir)*spd  (FROM N → southward = lat-)
        // dLon = -sin(dir)*spd/cosLat
        p.lat += -math.cos(rad) * spd * _kn2DegSec * _vizMult * dt;
        p.lon += -math.sin(rad) * spd * _kn2DegSec * _vizMult * dt / cosLat;
      }
      p.age += dt;

      // Reset if out of grid or expired
      final oob = p.lat < p.minLt || p.lat > p.maxLt
               || p.lon < p.minLn || p.lon > p.maxLn;
      if (oob || p.age >= p.maxAge) {
        p.lat = p.minLt + rng.nextDouble() * (p.maxLt - p.minLt);
        p.lon = p.minLn + rng.nextDouble() * (p.maxLn - p.minLn);
        p.prevLat = p.lat;
        p.prevLon = p.lon;
        p.age    = 0;
        p.maxAge = 8 + rng.nextDouble() * 14;
      }
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return RepaintBoundary(
      child: CustomPaint(
        painter: _ParticlePainter(
          camera:   camera,
          particles: _particles,
          windGrid: widget.windGrid,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// CustomPainter
// ---------------------------------------------------------------------------

class _ParticlePainter extends CustomPainter {
  final MapCamera camera;
  final List<_Particle> particles;
  final List<WindGridPoint> windGrid;

  const _ParticlePainter({
    required this.camera,
    required this.particles,
    required this.windGrid,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));

    for (final p in particles) {
      final cur  = camera.latLngToScreenPoint(LatLng(p.lat,     p.lon));
      final prev = camera.latLngToScreenPoint(LatLng(p.prevLat, p.prevLon));

      // Find colour from nearest grid wind
      WindGridPoint? near;
      var bestD = double.infinity;
      for (final g in windGrid) {
        final d = (g.lat - p.lat) * (g.lat - p.lat)
                + (g.lon - p.lon) * (g.lon - p.lon);
        if (d < bestD) { bestD = d; near = g; }
      }
      final color = _bftColor(near?.windSpeed ?? 0);

      // Fade in/out by particle age
      final frac = p.age / p.maxAge;
      final fade = (frac < 0.12 ? frac / 0.12 : frac > 0.80 ? (1 - frac) / 0.20 : 1.0)
          .clamp(0.0, 1.0);
      final a = p.alpha * fade;

      // Tail — only if the screen displacement is small (no map-wrap artefact)
      final dx = cur.x - prev.x;
      final dy = cur.y - prev.y;
      final dist2 = dx * dx + dy * dy;
      if (dist2 > 0.25 && dist2 < 2500) { // 0.5px…50px
        canvas.drawLine(
          Offset(prev.x.toDouble(), prev.y.toDouble()),
          Offset(cur.x.toDouble(),  cur.y.toDouble()),
          Paint()
            ..strokeWidth = 1.4
            ..style = PaintingStyle.stroke
            ..color = color.withOpacity(a * 0.72),
        );
      }

      // Head
      canvas.drawCircle(
        Offset(cur.x.toDouble(), cur.y.toDouble()),
        1.6,
        Paint()..color = color.withOpacity(a),
      );
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => true; // always animated
}

// ---------------------------------------------------------------------------
// Particle state
// ---------------------------------------------------------------------------

class _Particle {
  double lat, lon, prevLat, prevLon, age, maxAge;
  final double alpha, minLt, maxLt, minLn, maxLn;

  _Particle({
    required double lat,
    required double lon,
    required this.maxAge,
    required this.alpha,
    required this.minLt,
    required this.maxLt,
    required this.minLn,
    required this.maxLn,
  })  : lat = lat,
        lon = lon,
        prevLat = lat,
        prevLon = lon,
        age = 0;
}

// ---------------------------------------------------------------------------
// Beaufort colour helper (same scale as weather_screen)
// ---------------------------------------------------------------------------

Color _bftColor(double kn) {
  if (kn >= 34) return const Color(0xFFFF453A);
  if (kn >= 22) return const Color(0xFFFF9F0A);
  if (kn >= 11) return const Color(0xFFFFD60A);
  return const Color(0xFF30D158);
}
