import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../models/weather_state.dart';
import '../providers/vessel_provider.dart';
import '../providers/settings_provider.dart';

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final weatherProvider = NotifierProvider<WeatherNotifier, WeatherState>(
  WeatherNotifier.new,
);

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class WeatherNotifier extends Notifier<WeatherState> {
  static const _refreshInterval = Duration(minutes: 30);
  Timer? _timer;

  @override
  WeatherState build() {
    ref.onDispose(() {
      _timer?.cancel();
    });

    // When vessel position arrives from Signal K, trigger a fetch
    // (runs once and only when position transitions from null → non-null)
    ref.listen(
      vesselProvider.select((v) => v.position),
      (prev, next) {
        if (next != null && (next.latitude != 0.0 || next.longitude != 0.0)) {
          // Only auto-fetch if we don't have weather data yet
          if (state.condition == null && !state.isLoading) {
            _fetch();
          }
        }
      },
    );

    // Also try on startup after a short delay (in case SK is already connected)
    Future.delayed(const Duration(seconds: 5), _fetch);
    _timer = Timer.periodic(_refreshInterval, (_) => _fetch());
    return const WeatherState.empty();
  }

  Future<void> refresh() => _fetch();

  Future<void> _fetch() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      // 1. Resolve position — vessel GPS first, then device GPS
      final pos = await _resolvePosition();
      if (pos == null) {
        state = state.copyWith(
          isLoading: false,
          error: '无法获取位置，请检查定位权限（设置 → 定位服务）',
        );
        return;
      }

      // 2. Try MetService NZ if configured; fall back to Open-Meteo
      final settings = ref.read(settingsProvider);
      WeatherState? result;

      if (settings.metServiceApiKey.isNotEmpty) {
        result = await _fetchMetService(
          lat: pos.latitude,
          lon: pos.longitude,
          apiKey: settings.metServiceApiKey,
        );
      }

      result ??= await _fetchOpenMeteo(lat: pos.latitude, lon: pos.longitude);

      state = result.copyWith(isLoading: false, error: null);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  // --------------------------------------------------------------------------
  // Position resolution
  // --------------------------------------------------------------------------

  Future<_LatLon?> _resolvePosition() async {
    // 1. Prefer vessel GPS from Signal K (authoritative nav GPS)
    final vessel = ref.read(vesselProvider);
    final vPos = vessel.position;
    if (vPos != null && (vPos.latitude != 0.0 || vPos.longitude != 0.0)) {
      return _LatLon(vPos.latitude, vPos.longitude);
    }

    // 2. Try device GPS — check permission first
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever ||
          perm == LocationPermission.denied) {
        return null;
      }

      // 3. Last known position — instant, no GPS fix needed
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) return _LatLon(last.latitude, last.longitude);

      // 4. Fresh GPS fix (8 s timeout)
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
        timeLimit: const Duration(seconds: 8),
      );
      return _LatLon(pos.latitude, pos.longitude);
    } catch (_) {
      return null;
    }
  }

  // --------------------------------------------------------------------------
  // Open-Meteo (free, no API key, global coverage — perfect for maritime)
  // https://open-meteo.com/
  // --------------------------------------------------------------------------

  Future<WeatherState> _fetchOpenMeteo({
    required double lat,
    required double lon,
  }) async {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': lat.toStringAsFixed(4),
      'longitude': lon.toStringAsFixed(4),
      'current': 'temperature_2m,apparent_temperature,weather_code'
          ',wind_speed_10m,wind_direction_10m,precipitation',
      'wind_speed_unit': 'kn',
      'timezone': 'auto',
    });

    final resp = await http
        .get(uri, headers: {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 15));

    if (resp.statusCode != 200) {
      throw Exception('Open-Meteo HTTP ${resp.statusCode}: '
          '${resp.body.length > 120 ? resp.body.substring(0, 120) : resp.body}');
    }

    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final cur = body['current'] as Map<String, dynamic>?;
    if (cur == null) {
      throw Exception('Open-Meteo: 响应中无 current 字段，body=${resp.body.substring(0, 200)}');
    }

    final code = (cur['weather_code'] as num?)?.toInt() ?? 0;
    final lat4 = lat.toStringAsFixed(2);
    final lon4 = lon.toStringAsFixed(2);

    return WeatherState(
      temperature: (cur['temperature_2m'] as num?)?.toDouble(),
      feelsLike: (cur['apparent_temperature'] as num?)?.toDouble(),
      weatherCode: code,
      condition: conditionFromCode(code),
      windSpeed: (cur['wind_speed_10m'] as num?)?.toDouble(),
      windDirection: (cur['wind_direction_10m'] as num?)?.toInt(),
      precipitation: (cur['precipitation'] as num?)?.toDouble(),
      description: descriptionForCode(code),
      fetchedAt: DateTime.now(),
      locationLabel: '$lat4°, $lon4°',
    );
  }

  // --------------------------------------------------------------------------
  // MetService NZ (commercial API — requires API key from data.metservice.com)
  // Register at https://data.metservice.com/ to get a key.
  // --------------------------------------------------------------------------

  Future<WeatherState?> _fetchMetService({
    required double lat,
    required double lon,
    required String apiKey,
  }) async {
    try {
      final uri = Uri.https('data.metservice.com', '/v1/point_forecast', {
        'lat': lat.toStringAsFixed(4),
        'lon': lon.toStringAsFixed(4),
      });
      final resp = await http
          .get(uri, headers: {'apikey': apiKey, 'Accept': 'application/json'})
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null; // fall through to Open-Meteo

      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      // MetService response schema varies; extract current conditions
      final current = body['current'] as Map<String, dynamic>?;
      if (current == null) return null;

      // Temperature in °C
      final tempC = (current['airTemperature'] as num?)?.toDouble();
      // Wind speed — MetService returns m/s; convert to knots (×1.944)
      final windMs = (current['windSpeed'] as num?)?.toDouble();
      final windKn = windMs != null ? windMs * 1.944 : null;
      final windDir = (current['windDirection'] as num?)?.toInt();
      // MetService weather symbol code → use a simple mapping
      final symbolCode = current['symbolCode'] as String? ?? '';
      final (code, description) = _metServiceSymbolToWmo(symbolCode);
      final condition = conditionFromCode(code);

      return WeatherState(
        temperature: tempC,
        feelsLike: tempC, // MetService doesn't always provide feels-like
        weatherCode: code,
        condition: condition,
        windSpeed: windKn,
        windDirection: windDir,
        precipitation: (current['precipitation'] as num?)?.toDouble(),
        description: description,
        fetchedAt: DateTime.now(),
        locationLabel: 'MetService NZ',
      );
    } catch (_) {
      return null;
    }
  }

  /// Map MetService symbol codes to WMO codes + Chinese description.
  (int, String) _metServiceSymbolToWmo(String symbol) {
    if (symbol.contains('sun') || symbol.contains('clear')) return (0, '晴朗');
    if (symbol.contains('few_cloud') || symbol.contains('partly')) return (2, '局部多云');
    if (symbol.contains('cloud')) return (3, '多云');
    if (symbol.contains('fog')) return (45, '有雾');
    if (symbol.contains('drizzle')) return (51, '毛毛雨');
    if (symbol.contains('heavy_rain') || symbol.contains('rain_heavy')) return (65, '大雨');
    if (symbol.contains('rain')) return (61, '小雨');
    if (symbol.contains('snow')) return (71, '降雪');
    if (symbol.contains('thunder')) return (95, '雷阵雨');
    return (1, '基本晴朗');
  }
}

// ---------------------------------------------------------------------------
// Internal helper
// ---------------------------------------------------------------------------

class _LatLon {
  final double latitude;
  final double longitude;
  const _LatLon(this.latitude, this.longitude);
}
