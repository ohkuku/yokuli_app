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
    // Kick off first fetch after a short delay so startup doesn't block
    Future.delayed(const Duration(seconds: 3), _fetch);
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
          error: '无法获取位置，请允许定位权限',
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

      if (result != null) {
        state = result.copyWith(isLoading: false, error: null);
      } else {
        state = state.copyWith(
          isLoading: false,
          error: '天气数据获取失败，请检查网络',
        );
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: '天气获取错误: $e',
      );
    }
  }

  // --------------------------------------------------------------------------
  // Position resolution
  // --------------------------------------------------------------------------

  Future<_LatLon?> _resolvePosition() async {
    // Prefer vessel GPS from Signal K
    final vessel = ref.read(vesselProvider);
    final vPos = vessel.position;
    if (vPos != null && vPos.latitude != 0.0) {
      return _LatLon(vPos.latitude, vPos.longitude);
    }

    // Fall back to device GPS
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever ||
          perm == LocationPermission.denied) {
        return null;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 8),
        ),
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

  Future<WeatherState?> _fetchOpenMeteo({
    required double lat,
    required double lon,
  }) async {
    final uri = Uri.parse(
      'https://api.open-meteo.com/v1/forecast'
      '?latitude=${lat.toStringAsFixed(4)}'
      '&longitude=${lon.toStringAsFixed(4)}'
      '&current=temperature_2m,apparent_temperature,weather_code'
      ',wind_speed_10m,wind_direction_10m,precipitation'
      '&wind_speed_unit=knots'
      '&timezone=auto',
    );

    final resp = await http.get(uri).timeout(const Duration(seconds: 12));
    if (resp.statusCode != 200) return null;

    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final cur = body['current'] as Map<String, dynamic>?;
    if (cur == null) return null;

    final code = (cur['weather_code'] as num?)?.toInt() ?? 0;
    final condition = conditionFromCode(code);
    final lat4 = lat.toStringAsFixed(2);
    final lon4 = lon.toStringAsFixed(2);

    return WeatherState(
      temperature: (cur['temperature_2m'] as num?)?.toDouble(),
      feelsLike: (cur['apparent_temperature'] as num?)?.toDouble(),
      weatherCode: code,
      condition: condition,
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
      final uri = Uri.parse(
        'https://data.metservice.com/v1/point_forecast'
        '?lat=${lat.toStringAsFixed(4)}'
        '&lon=${lon.toStringAsFixed(4)}',
      );
      final resp = await http
          .get(uri, headers: {'apikey': apiKey})
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null;

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
