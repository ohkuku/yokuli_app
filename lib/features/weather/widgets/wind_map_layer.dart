import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/models/weather_state.dart';

// Callback type: (centerLat, centerLon, stepDeg, gridN)
typedef WindGridRefetch = void Function(double lat, double lon, double step, int n);

// ---------------------------------------------------------------------------
// Public entry-point
// ---------------------------------------------------------------------------

/// Full Windy-style zoomable regional weather map.
///
/// Supports multiple data layers (wind particles, wave heatmap, pressure
/// isolines, rain heatmap), model selector, timeline playback, and
/// tap-to-forecast.
class WindMapWidget extends StatefulWidget {
  // Current-time grids
  final List<WindGridPoint> windGrid;
  final List<WaveGridPoint> waveGrid;

  // Timeline (for playback)
  final List<MapGridSnapshot> forecastTimeline;

  // Active layer / model / time step
  final WindLayer activeLayer;
  final ForecastModel model;
  final int timeStepIndex; // 0 = now, 1..5 = future steps

  final double centerLat;
  final double centerLon;
  final double? vesselLat;
  final double? vesselLon;

  // Callbacks
  final WindGridRefetch? onGridNeeded;
  final Function(LatLng)? onMapTap;

  const WindMapWidget({
    super.key,
    required this.windGrid,
    this.waveGrid = const [],
    this.forecastTimeline = const [],
    this.activeLayer = WindLayer.wind,
    this.model = ForecastModel.gfs,
    this.timeStepIndex = 0,
    required this.centerLat,
    required this.centerLon,
    this.vesselLat,
    this.vesselLon,
    this.onGridNeeded,
    this.onMapTap,
  });

  @override
  State<WindMapWidget> createState() => _WindMapWidgetState();
}

class _WindMapWidgetState extends State<WindMapWidget> {
  final _mapController = MapController();
  double? _lastFetchLat, _lastFetchLon, _lastFetchStep;
  Timer? _refetchDebounce;

  static const _gridN = 9;

  List<WindGridPoint> get _activeWindGrid {
    if (widget.timeStepIndex == 0 || widget.forecastTimeline.isEmpty) {
      return widget.windGrid;
    }
    final idx = widget.timeStepIndex.clamp(0, widget.forecastTimeline.length - 1);
    return widget.forecastTimeline[idx].windPoints;
  }

  List<WaveGridPoint> get _activeWaveGrid {
    if (widget.timeStepIndex == 0 || widget.forecastTimeline.isEmpty) {
      return widget.waveGrid;
    }
    final idx = widget.timeStepIndex.clamp(0, widget.forecastTimeline.length - 1);
    return widget.forecastTimeline[idx].wavePoints;
  }

  void _onMapEvent(MapEvent event) {
    if (event is! MapEventMoveEnd) return;
    // Debounce: wait 600ms after the last move before firing
    _refetchDebounce?.cancel();
    _refetchDebounce = Timer(const Duration(milliseconds: 600), _checkAndRefetch);
  }

  void _checkAndRefetch() {
    if (widget.onGridNeeded == null) return;
    final camera = _mapController.camera;
    final bounds  = camera.visibleBounds;
    final visSpan = math.max(bounds.north - bounds.south, bounds.east - bounds.west);
    final step    = (visSpan / _gridN).clamp(0.25, 5.0);
    final newLat  = camera.center.latitude;
    final newLon  = camera.center.longitude;

    final latDiff  = (_lastFetchLat  == null) ? double.infinity : (newLat - _lastFetchLat!).abs();
    final lonDiff  = (_lastFetchLon  == null) ? double.infinity : (newLon - _lastFetchLon!).abs();
    final stepDiff = (_lastFetchStep == null) ? double.infinity : (step - _lastFetchStep!).abs() / step;
    if (latDiff < step * 0.5 && lonDiff < step * 0.5 && stepDiff < 0.2) return;

    _lastFetchLat  = newLat;
    _lastFetchLon  = newLon;
    _lastFetchStep = step;
    widget.onGridNeeded!(newLat, newLon, step, _gridN);
  }

  @override
  void dispose() {
    _refetchDebounce?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final windGrid = _activeWindGrid;
    final waveGrid = _activeWaveGrid;

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: LatLng(widget.centerLat, widget.centerLon),
        initialZoom: 7.0,
        minZoom: 4.0,
        maxZoom: 12.0,
        // Disable rotation — pinch zoom only changes scale, not heading
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
        onMapEvent: _onMapEvent,
        onTap: widget.onMapTap != null
            ? (tapPos, latLng) => widget.onMapTap!(latLng)
            : null,
      ),
      children: [
        // Base tiles — dark style for contrast
        TileLayer(
          urlTemplate:
              'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
          subdomains: const ['a', 'b', 'c', 'd'],
          retinaMode: true,
          userAgentPackageName: 'com.yokuli.app',
        ),

        // ── Layer-specific rendering ────────────────────────────────────────
        if (widget.activeLayer == WindLayer.wind && windGrid.isNotEmpty)
          _WindParticleLayer(windGrid: windGrid),

        if (widget.activeLayer == WindLayer.waves)
          _HeatmapLayer(
            points: waveGrid
                .where((p) => p.waveHeight != null)
                .map((p) => _HeatPoint(p.lat, p.lon, p.waveHeight!))
                .toList(),
            minVal: 0,
            maxVal: 6,
            colorAt: _waveColor,
          ),

        if (widget.activeLayer == WindLayer.pressure)
          _IsobarLayer(windGrid: windGrid),

        if (widget.activeLayer == WindLayer.rain)
          _HeatmapLayer(
            points: windGrid
                .where((p) => p.precipitation != null)
                .map((p) => _HeatPoint(p.lat, p.lon, p.precipitation!))
                .toList(),
            minVal: 0,
            maxVal: 10,
            colorAt: _rainColor,
          ),

        // ── Arrow markers ───────────────────────────────────────────────────
        if (widget.activeLayer == WindLayer.wind)
          MarkerLayer(
            markers: windGrid
                .where((p) => p.windSpeed != null && p.windDir != null)
                .map((p) => Marker(
                      point: LatLng(p.lat, p.lon),
                      width: 18,
                      height: 18,
                      child: Transform.rotate(
                        angle: (p.windDir! + 180) * math.pi / 180.0,
                        child: Icon(Icons.arrow_upward_rounded,
                            size: 12,
                            color: _bftColor(p.windSpeed!).withOpacity(0.65)),
                      ),
                    ))
                .toList(),
          ),

        if (widget.activeLayer == WindLayer.waves)
          MarkerLayer(
            markers: waveGrid
                .where((p) => p.waveDir != null && p.waveHeight != null)
                .map((p) => Marker(
                      point: LatLng(p.lat, p.lon),
                      width: 20,
                      height: 20,
                      child: Transform.rotate(
                        angle: (p.waveDir! + 180) * math.pi / 180.0,
                        child: Icon(Icons.arrow_upward_rounded,
                            size: 12,
                            color: _waveColor(p.waveHeight! / 6).withOpacity(0.70)),
                      ),
                    ))
                .toList(),
          ),

        // ── Vessel marker ───────────────────────────────────────────────────
        if (widget.vesselLat != null && widget.vesselLon != null)
          MarkerLayer(
            markers: [
              Marker(
                point: LatLng(widget.vesselLat!, widget.vesselLon!),
                width: 28,
                height: 28,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.cyanAccent.withOpacity(0.2),
                    border: Border.all(color: Colors.cyanAccent, width: 1.5),
                  ),
                  child: const Icon(Icons.navigation_rounded,
                      color: Colors.cyanAccent, size: 14),
                ),
              ),
            ],
          ),

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
// Wind particle layer
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

  static const _count     = 200;
  static const _vizMult   = 3500.0;
  static const _kn2DegSec = 1.0 / (3600.0 * 60.0);

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
      alpha: 0.45 + rng.nextDouble() * 0.55,
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
        p.lat += -math.cos(rad) * spd * _kn2DegSec * _vizMult * dt;
        p.lon += -math.sin(rad) * spd * _kn2DegSec * _vizMult * dt / cosLat;
      }
      p.age += dt;
      final oob = p.lat < p.minLt || p.lat > p.maxLt
               || p.lon < p.minLn || p.lon > p.maxLn;
      if (oob || p.age >= p.maxAge) {
        p.lat     = p.minLt + rng.nextDouble() * (p.maxLt - p.minLt);
        p.lon     = p.minLn + rng.nextDouble() * (p.maxLn - p.minLn);
        p.prevLat = p.lat;
        p.prevLon = p.lon;
        p.age     = 0;
        p.maxAge  = 8 + rng.nextDouble() * 14;
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
            camera: camera, particles: _particles, windGrid: widget.windGrid),
      ),
    );
  }
}

class _ParticlePainter extends CustomPainter {
  final MapCamera camera;
  final List<_Particle> particles;
  final List<WindGridPoint> windGrid;

  const _ParticlePainter(
      {required this.camera, required this.particles, required this.windGrid});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));
    for (final p in particles) {
      final cur  = camera.latLngToScreenPoint(LatLng(p.lat,     p.lon));
      final prev = camera.latLngToScreenPoint(LatLng(p.prevLat, p.prevLon));
      WindGridPoint? near;
      var bestD = double.infinity;
      for (final g in windGrid) {
        final d = (g.lat - p.lat) * (g.lat - p.lat)
                + (g.lon - p.lon) * (g.lon - p.lon);
        if (d < bestD) { bestD = d; near = g; }
      }
      final color = _bftColor(near?.windSpeed ?? 0);
      final frac = p.age / p.maxAge;
      final fade = (frac < 0.12
          ? frac / 0.12
          : frac > 0.80 ? (1 - frac) / 0.20 : 1.0).clamp(0.0, 1.0);
      final a = p.alpha * fade;
      final dx = cur.x - prev.x;
      final dy = cur.y - prev.y;
      final dist2 = dx * dx + dy * dy;
      if (dist2 > 0.25 && dist2 < 2500) {
        canvas.drawLine(
          Offset(prev.x.toDouble(), prev.y.toDouble()),
          Offset(cur.x.toDouble(),  cur.y.toDouble()),
          Paint()
            ..strokeWidth = 1.4
            ..style = PaintingStyle.stroke
            ..color = color.withOpacity(a * 0.72),
        );
      }
      canvas.drawCircle(
        Offset(cur.x.toDouble(), cur.y.toDouble()), 1.6,
        Paint()..color = color.withOpacity(a),
      );
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => true;
}

// ---------------------------------------------------------------------------
// Heatmap layer (waves / rain / SST)
// ---------------------------------------------------------------------------

class _HeatPoint {
  final double lat, lon, value;
  const _HeatPoint(this.lat, this.lon, this.value);
}

class _HeatmapLayer extends StatelessWidget {
  final List<_HeatPoint> points;
  final double minVal, maxVal;
  final Color Function(double t) colorAt;

  const _HeatmapLayer({
    required this.points,
    required this.minVal,
    required this.maxVal,
    required this.colorAt,
  });

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return SizedBox.expand(
      child: CustomPaint(
        painter: _HeatmapPainter(
          camera: camera,
          points: points,
          minVal: minVal,
          maxVal: maxVal,
          colorAt: colorAt,
        ),
      ),
    );
  }
}

class _HeatmapPainter extends CustomPainter {
  final MapCamera camera;
  final List<_HeatPoint> points;
  final double minVal, maxVal;
  final Color Function(double t) colorAt;

  const _HeatmapPainter({
    required this.camera,
    required this.points,
    required this.minVal,
    required this.maxVal,
    required this.colorAt,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    // Compute on-screen grid spacing from adjacent points so blobs overlap.
    // We want radius ≥ half-spacing so there are no gaps between cells.
    double radius = 40;
    if (points.length >= 2) {
      final p0 = camera.latLngToScreenPoint(LatLng(points[0].lat, points[0].lon));
      final p1 = camera.latLngToScreenPoint(LatLng(points[1].lat, points[1].lon));
      final dx = (p1.x - p0.x).abs();
      final dy = (p1.y - p0.y).abs();
      final spacing = math.max(dx, dy); // use the longer axis
      radius = spacing * 0.75; // 75% of spacing → smooth overlap
    }
    radius = radius.clamp(20.0, 200.0);

    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));

    for (final p in points) {
      final sp = camera.latLngToScreenPoint(LatLng(p.lat, p.lon));
      final t  = ((p.value - minVal) / (maxVal - minVal)).clamp(0.0, 1.0);
      final c  = colorAt(t);
      final cx = sp.x.toDouble();
      final cy = sp.y.toDouble();
      canvas.drawCircle(
        Offset(cx, cy),
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [c.withOpacity(0.60), c.withOpacity(0.0)],
            stops: const [0.4, 1.0],
          ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: radius)),
      );
    }
  }

  @override
  // Camera doesn't implement ==, so always repaint when camera or data changes.
  bool shouldRepaint(_HeatmapPainter old) => true;
}

// ---------------------------------------------------------------------------
// Isobar layer (pressure contours)
// ---------------------------------------------------------------------------

class _IsobarLayer extends StatelessWidget {
  final List<WindGridPoint> windGrid;
  const _IsobarLayer({required this.windGrid});

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return SizedBox.expand(
      child: CustomPaint(
        painter: _IsobarPainter(camera: camera, windGrid: windGrid),
      ),
    );
  }
}

class _IsobarPainter extends CustomPainter {
  final MapCamera camera;
  final List<WindGridPoint> windGrid;

  const _IsobarPainter({required this.camera, required this.windGrid});

  @override
  void paint(Canvas canvas, Size size) {
    if (windGrid.isEmpty) return;
    final n = math.sqrt(windGrid.length.toDouble()).round();
    if (n < 2) return;

    // Check we actually have pressure data before drawing
    final hasPressure = windGrid.any((p) => p.pressure != null);
    if (!hasPressure) return;

    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));

    // Background pressure-colored heatmap so you can see field even between lines
    for (final pt in windGrid) {
      if (pt.pressure == null) continue;
      final sp = camera.latLngToScreenPoint(LatLng(pt.lat, pt.lon));
      final t  = ((pt.pressure! - 980) / 50).clamp(0.0, 1.0);
      final c  = _isobarColor(pt.pressure!);
      canvas.drawCircle(
        Offset(sp.x.toDouble(), sp.y.toDouble()),
        _cellRadius(camera, windGrid),
        Paint()
          ..shader = RadialGradient(
            colors: [c.withOpacity(0.25), c.withOpacity(0.0)],
            stops: const [0.3, 1.0],
          ).createShader(Rect.fromCircle(
            center: Offset(sp.x.toDouble(), sp.y.toDouble()),
            radius: _cellRadius(camera, windGrid),
          )),
      );
    }

    // Isobar contour lines at every 4 hPa
    final pressures = windGrid.map((p) => p.pressure ?? 0).toList();
    final pMin = (pressures.reduce(math.min) / 4).floor() * 4.0;
    final pMax = (pressures.reduce(math.max) / 4).ceil() * 4.0;

    for (double level = pMin; level <= pMax; level += 4) {
      final isMajor = level % 8 == 0;
      final paint = Paint()
        ..color = _isobarColor(level).withOpacity(isMajor ? 0.90 : 0.55)
        ..strokeWidth = isMajor ? 1.8 : 0.9
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      for (int r = 0; r < n - 1; r++) {
        for (int c = 0; c < n - 1; c++) {
          // Full square cell: draw both diagonal triangles
          final i00 = r * n + c;
          final i10 = (r + 1) * n + c;
          final i01 = r * n + (c + 1);
          final i11 = (r + 1) * n + (c + 1);
          if (i11 >= windGrid.length) continue;
          _drawIsoSegment(canvas, paint, camera, level,
              windGrid[i00], windGrid[i10], windGrid[i01]);
          _drawIsoSegment(canvas, paint, camera, level,
              windGrid[i10], windGrid[i11], windGrid[i01]);
        }
      }

      // Label major isobars once in the middle of the grid
      if (isMajor) {
        final mid = windGrid[windGrid.length ~/ 2];
        if ((mid.pressure ?? 0) - level < 4) {
          _drawIsoLabel(canvas, camera, mid.lat, mid.lon, '${level.round()} hPa',
              _isobarColor(level));
        }
      }
    }
  }

  double _cellRadius(MapCamera camera, List<WindGridPoint> grid) {
    if (grid.length < 2) return 40;
    final p0 = camera.latLngToScreenPoint(LatLng(grid[0].lat, grid[0].lon));
    final p1 = camera.latLngToScreenPoint(LatLng(grid[1].lat, grid[1].lon));
    final dx = (p1.x - p0.x).abs();
    final dy = (p1.y - p0.y).abs();
    return math.max(dx, dy).clamp(20.0, 200.0) * 0.75;
  }

  void _drawIsoLabel(Canvas canvas, MapCamera camera, double lat, double lon,
      String text, Color color) {
    final sp = camera.latLngToScreenPoint(LatLng(lat, lon));
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
            color: color.withOpacity(0.85),
            fontSize: 10,
            fontWeight: FontWeight.w700,
            shadows: const [Shadow(color: Colors.black, blurRadius: 4)]),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(sp.x - tp.width / 2, sp.y - tp.height / 2));
  }

  void _drawIsoSegment(Canvas canvas, Paint paint, MapCamera camera, double level,
      WindGridPoint a, WindGridPoint b, WindGridPoint c) {
    if (a.pressure == null || b.pressure == null || c.pressure == null) return;
    final va = a.pressure!, vb = b.pressure!, vc = c.pressure!;
    final crossings = <Offset>[];

    void addCross(WindGridPoint p1, WindGridPoint p2, double v1, double v2) {
      if ((v1 < level) != (v2 < level)) {
        final t = (level - v1) / (v2 - v1);
        final sp = camera.latLngToScreenPoint(LatLng(
          p1.lat + (p2.lat - p1.lat) * t,
          p1.lon + (p2.lon - p1.lon) * t,
        ));
        crossings.add(Offset(sp.x.toDouble(), sp.y.toDouble()));
      }
    }

    addCross(a, b, va, vb);
    addCross(b, c, vb, vc);
    addCross(a, c, va, vc);
    if (crossings.length == 2) canvas.drawLine(crossings[0], crossings[1], paint);
  }

  Color _isobarColor(double hpa) {
    if (hpa < 990)  return const Color(0xFF5E81F4); // deep low
    if (hpa < 1000) return const Color(0xFF00C8FF); // low
    if (hpa < 1010) return const Color(0xFF30D158); // below normal
    if (hpa < 1020) return const Color(0xFFFFD60A); // normal-high
    if (hpa < 1025) return const Color(0xFFFF9F0A); // high
    return const Color(0xFFFF453A);                 // very high
  }

  @override
  bool shouldRepaint(_IsobarPainter old) => true; // always: camera changes on zoom/pan
}

// ---------------------------------------------------------------------------
// Particle data
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
  })  : lat     = lat,
        lon     = lon,
        prevLat = lat,
        prevLon = lon,
        age     = 0;
}

// ---------------------------------------------------------------------------
// Color helpers
// ---------------------------------------------------------------------------

Color _bftColor(double kn) {
  if (kn >= 34) return const Color(0xFFFF453A); // gale force 8+
  if (kn >= 22) return const Color(0xFFFF9F0A); // near-gale 7
  if (kn >= 11) return const Color(0xFFFFD60A); // moderate 4-6
  return const Color(0xFF30D158);               // light 0-3
}

/// Wave height colour — green=calm, yellow=moderate, orange=rough, red=very rough
/// maxVal = 6m
Color _waveColor(double t) {
  if (t > 0.75) return const Color(0xFFFF453A); // >4.5m — very rough/high
  if (t > 0.50) return const Color(0xFFFF9F0A); // 3–4.5m — rough
  if (t > 0.25) return const Color(0xFFFFD60A); // 1.5–3m — moderate
  return const Color(0xFF30D158);               // <1.5m — calm/slight
}

/// Rain colour — light blue=drizzle, blue=moderate, deep blue/purple=heavy
Color _rainColor(double t) {
  if (t > 0.70) return const Color(0xFF5E4FE4); // >7 mm/h — heavy
  if (t > 0.40) return const Color(0xFF3080F4); // 4–7 mm/h — moderate
  if (t > 0.10) return const Color(0xFF30C8F4); // 1–4 mm/h — light
  return const Color(0xFF90EAF9).withOpacity(0.5); // trace
}

// ---------------------------------------------------------------------------
// Legend widget — shown bottom-left of the map for non-wind layers
// ---------------------------------------------------------------------------

/// A compact horizontal colour legend bar for heatmap layers.
class MapLayerLegend extends StatelessWidget {
  final String title;
  final List<(Color, String)> entries;

  const MapLayerLegend({super.key, required this.title, required this.entries});

  const MapLayerLegend.wave({super.key})
      : title = '浪高 (m)',
        entries = const [
          (Color(0xFF30D158), '<1.5m'),
          (Color(0xFFFFD60A), '1.5–3m'),
          (Color(0xFFFF9F0A), '3–4.5m'),
          (Color(0xFFFF453A), '>4.5m'),
        ];

  const MapLayerLegend.rain({super.key})
      : title = '降雨 (mm/h)',
        entries = const [
          (Color(0xFF90EAF9), '微量'),
          (Color(0xFF30C8F4), '1–4'),
          (Color(0xFF3080F4), '4–7'),
          (Color(0xFF5E4FE4), '>7'),
        ];

  const MapLayerLegend.pressure({super.key})
      : title = '气压 (hPa)',
        entries = const [
          (Color(0xFF5E81F4), '<990'),
          (Color(0xFF30D158), '1000–1015'),
          (Color(0xFFFFD60A), '1015–1025'),
          (Color(0xFFFF453A), '>1025'),
        ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.68),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title,
              style: const TextStyle(
                  color: Colors.white60, fontSize: 9, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: entries.map((e) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 10, height: 10,
                  decoration: BoxDecoration(
                    color: e.$1,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 3),
                Text(e.$2,
                    style: const TextStyle(color: Colors.white70, fontSize: 9)),
              ]),
            )).toList(),
          ),
        ],
      ),
    );
  }
}
