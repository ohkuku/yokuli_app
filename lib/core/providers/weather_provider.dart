import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../models/weather_state.dart';
import '../providers/vessel_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/lan_broadcast.dart';

// ignore_for_file: avoid_catches_without_on_clauses

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

  /// Apply weather data received from a LAN peer (no API call needed).
  /// Only applied if the peer's data is fresher than the local data, or if we
  /// have no data yet, to prevent overwriting a recent local fetch.
  void applyRemoteSync(Map<String, dynamic> data) {
    try {
      final fetchedAtStr = data['fetchedAt'] as String?;
      final remoteFetchedAt = fetchedAtStr != null ? DateTime.tryParse(fetchedAtStr) : null;
      // Guard: don't overwrite local data if ours is newer
      if (remoteFetchedAt != null &&
          state.fetchedAt != null &&
          state.fetchedAt!.isAfter(remoteFetchedAt)) {
        return;
      }
      // Also don't apply if we are currently loading fresh data
      if (state.isLoading) return;

      final conditionName = data['condition'] as String?;
      WeatherCondition? condition;
      if (conditionName != null) {
        condition = WeatherCondition.values.where((c) => c.name == conditionName).firstOrNull;
      }
      final weatherCode = data['weatherCode'] as int?;

      state = state.copyWith(
        temperature: (data['temperature'] as num?)?.toDouble() ?? state.temperature,
        windSpeed: (data['windSpeed'] as num?)?.toDouble() ?? state.windSpeed,
        windDirection: (data['windDirection'] as num?)?.toInt() ?? state.windDirection,
        windGust: (data['windGust'] as num?)?.toDouble() ?? state.windGust,
        waveHeight: (data['waveHeight'] as num?)?.toDouble() ?? state.waveHeight,
        fetchedAt: remoteFetchedAt ?? state.fetchedAt,
        description: data['description'] as String? ?? state.description,
        weatherCode: weatherCode ?? state.weatherCode,
        condition: condition ?? (weatherCode != null ? conditionFromCode(weatherCode) : state.condition),
        locationLabel: data['locationLabel'] as String? ?? state.locationLabel,
        isLoading: false,
      );
    } catch (_) {}
  }

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

      // 2. MetService NZ is the only source
      final settings = ref.read(settingsProvider);

      if (settings.metServiceApiKey.isEmpty) {
        state = state.copyWith(
          isLoading: false,
          error: 'MetService API Key 未配置，请在设置中配置',
        );
        return;
      }

      final result = await _fetchMetService(
        lat: pos.latitude,
        lon: pos.longitude,
        apiKey: settings.metServiceApiKey,
      );

      if (result == null) {
        state = state.copyWith(
          isLoading: false,
          error: 'MetService 请求失败，请检查 API Key 和网络',
        );
        return;
      }

      // Fetch tides if WorldTides key is configured
      List<TideEntry> tides = const [];
      if (settings.worldTidesApiKey.isNotEmpty) {
        tides = await _fetchTides(
          lat: pos.latitude,
          lon: pos.longitude,
          apiKey: settings.worldTidesApiKey,
        );
      }

      state = result.copyWith(isLoading: false, error: null, tides: tides);

      // Broadcast fresh weather to all LAN peers — saves API quota on other
      // devices and ensures fleet-wide weather consistency.
      try {
        ref.read(lanBroadcastProvider)?.call({
          'type': 'weather_sync',
          'data': {
            'temperature': state.temperature,
            'windSpeed': state.windSpeed,
            'windDirection': state.windDirection,
            'windGust': state.windGust,
            'waveHeight': state.waveHeight,
            'fetchedAt': state.fetchedAt?.toIso8601String(),
            'description': state.description,
            'weatherCode': state.weatherCode,
            'condition': state.condition?.name,
            'locationLabel': state.locationLabel,
          },
        });
      } catch (_) {}
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
  // MetService NZ (commercial API — requires API key from data.metservice.com)
  // Register at https://data.metservice.com/ to get a key.
  // --------------------------------------------------------------------------

  // --------------------------------------------------------------------------
  // WorldTides API
  // --------------------------------------------------------------------------

  Future<List<TideEntry>> _fetchTides({
    required double lat, required double lon, required String apiKey,
  }) async {
    try {
      final uri = Uri.https('www.worldtides.info', '/api/v3', {
        'heights': '',
        'extremes': '',
        'lat': lat.toStringAsFixed(4),
        'lon': lon.toStringAsFixed(4),
        'key': apiKey,
        'days': '3',
        'stationDistance': '100',
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return [];
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      // Parse extremes (high/low tide markers)
      final extremes = body['extremes'] as List<dynamic>? ?? [];
      final tides = <TideEntry>[];
      for (final e in extremes) {
        if (e is! Map<String, dynamic>) continue;
        final dt = DateTime.tryParse(e['date'] as String? ?? '');
        if (dt == null) continue;
        final h = (e['height'] as num?)?.toDouble() ?? 0.0;
        final type = (e['type'] as String? ?? '').toLowerCase();
        tides.add(TideEntry(
          time: dt,
          height: h,
          isHighTide: type == 'high',
        ));
      }
      return tides;
    } catch (_) {
      return [];
    }
  }

  /// Validates WorldTides API key using Auckland position.
  /// Returns null on success (or if key is empty — key is optional).
  static Future<String?> validateWorldTidesKey(String apiKey) async {
    if (apiKey.isEmpty) return null; // optional key, empty = skip
    try {
      final uri = Uri.https('www.worldtides.info', '/api/v3', {
        'heights': '',
        'lat': '-36.8509',
        'lon': '174.7645',
        'key': apiKey,
        'days': '1',
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 12));
      if (resp.statusCode == 200) return null;
      if (resp.statusCode == 400 || resp.statusCode == 401 || resp.statusCode == 403) {
        return 'WorldTides API Key 无效 (HTTP ${resp.statusCode})';
      }
      return null; // other errors: don't block
    } on TimeoutException { return null; }
    catch (_) { return null; }
  }

  /// Tests MetService API key with a known NZ position (Wellington).
  /// Returns null on success, or an error string on failure.
  /// Only blocks for 401/403 (invalid key). Non-auth errors pass through.
  static Future<String?> validateApiKey(String apiKey) async {
    if (apiKey.isEmpty) return 'MetService API Key 未配置';
    try {
      final uri = Uri.https('data.metservice.com', '/v1/point_forecast', {
        'lat': '-41.2865',
        'lon': '174.7762',
      });
      final resp = await http
          .get(uri, headers: {
            'apikey': apiKey,
            'Accept': 'application/json',
          })
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode == 200) return null; // valid
      if (resp.statusCode == 401 || resp.statusCode == 403) {
        return 'API Key 无效 — 请检查密钥 (HTTP ${resp.statusCode})';
      }
      // For 404 and other errors: key might be valid but endpoint has issues.
      // Don't block app startup for non-auth errors.
      return null; // treat as "probably OK"
    } on TimeoutException {
      return null; // Don't block on timeout — might just be network issue
    } catch (e) {
      return null; // Don't block on connection errors
    }
  }

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
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return null;

      final body = jsonDecode(resp.body) as Map<String, dynamic>;

      // --- Current ---
      final current = body['current'] as Map<String, dynamic>? ?? {};
      final tempC = (current['airTemperature'] as num?)?.toDouble();
      final windMs = (current['windSpeed'] as num?)?.toDouble();
      final windKn = windMs != null ? windMs * 1.944 : null;
      final windDir = (current['windDirection'] as num?)?.toInt();
      final gustMs = (current['windGust'] as num?)?.toDouble();
      final gustKn = gustMs != null ? gustMs * 1.944 : null;
      final symbolCode = current['symbolCode'] as String? ?? '';
      final (code, description) = _metServiceSymbolToWmo(symbolCode);
      final waveHeight = (current['waveHeight'] as num?)?.toDouble();
      final wavePeriod = (current['wavePeriod'] as num?)?.toDouble();
      final swellHeight = (current['swellHeight'] as num?)?.toDouble();
      final swellDir = (current['swellDirection'] as num?)?.toInt();

      // --- Hourly ---
      final hourlyRaw = body['hourly'] as List<dynamic>? ?? [];
      final hourly = <HourlyForecast>[];
      for (final h in hourlyRaw) {
        if (h is! Map<String, dynamic>) continue;
        try {
          final t = DateTime.tryParse(h['time'] as String? ?? '');
          if (t == null) continue;
          final wSpeedMs = (h['windSpeed'] as num?)?.toDouble();
          final gMs = (h['windGust'] as num?)?.toDouble();
          hourly.add(HourlyForecast(
            time: t,
            temp: (h['airTemperature'] as num?)?.toDouble(),
            windSpeed: wSpeedMs != null ? wSpeedMs * 1.944 : null,
            windDir: (h['windDirection'] as num?)?.toInt(),
            windGust: gMs != null ? gMs * 1.944 : null,
            precip: (h['precipitation'] as num?)?.toDouble(),
            waveHeight: (h['waveHeight'] as num?)?.toDouble(),
            wavePeriod: (h['wavePeriod'] as num?)?.toDouble(),
            symbolCode: h['symbolCode'] as String?,
          ));
        } catch (_) {}
      }

      // --- Daily ---
      final dailyRaw = body['daily'] as List<dynamic>? ?? [];
      final daily = <DailyForecast>[];
      for (final d in dailyRaw) {
        if (d is! Map<String, dynamic>) continue;
        try {
          // Try 'date', 'time', or 'day' key
          final dateStr = (d['date'] ?? d['time'] ?? d['day']) as String?;
          if (dateStr == null) continue;
          final date = DateTime.tryParse(dateStr);
          if (date == null) continue;
          final maxWSpeedMs = (d['maxWindSpeed'] as num?)?.toDouble();
          daily.add(DailyForecast(
            date: date,
            tempMax: (d['maxTemperature'] ?? d['maxAirTemperature']) is num
                ? ((d['maxTemperature'] ?? d['maxAirTemperature']) as num)
                    .toDouble()
                : null,
            tempMin: (d['minTemperature'] ?? d['minAirTemperature']) is num
                ? ((d['minTemperature'] ?? d['minAirTemperature']) as num)
                    .toDouble()
                : null,
            windSpeedMax:
                maxWSpeedMs != null ? maxWSpeedMs * 1.944 : null,
            windDirDominant:
                (d['dominantWindDirection'] ?? d['windDirection']) is num
                    ? ((d['dominantWindDirection'] ?? d['windDirection']) as num)
                        .toInt()
                    : null,
            precipTotal:
                (d['totalPrecipitation'] ?? d['precipitation']) is num
                    ? ((d['totalPrecipitation'] ?? d['precipitation']) as num)
                        .toDouble()
                    : null,
            waveHeightMax:
                (d['maxWaveHeight'] ?? d['waveHeight']) is num
                    ? ((d['maxWaveHeight'] ?? d['waveHeight']) as num)
                        .toDouble()
                    : null,
            symbolCode: d['symbolCode'] as String?,
          ));
        } catch (_) {}
      }

      return WeatherState(
        temperature: tempC,
        feelsLike: (current['feelsLike'] as num?)?.toDouble() ?? tempC,
        weatherCode: code,
        condition: conditionFromCode(code),
        windSpeed: windKn,
        windDirection: windDir,
        windGust: gustKn,
        precipitation: (current['precipitation'] as num?)?.toDouble(),
        waveHeight: waveHeight,
        wavePeriod: wavePeriod,
        swellHeight: swellHeight,
        swellDirection: swellDir,
        description: description,
        fetchedAt: DateTime.now(),
        locationLabel: (body['location'] as Map<String, dynamic>?)?['name']
                as String? ??
            'MetService NZ',
        hourly: hourly,
        daily: daily,
      );
    } catch (_) {
      return null;
    }
  }

  /// Map MetService symbol codes to WMO codes + Chinese description.
  (int, String) _metServiceSymbolToWmo(String symbol) {
    if (symbol.contains('sun') || symbol.contains('clear')) return (0, '晴朗');
    if (symbol.contains('few_cloud') || symbol.contains('partly'))
      return (2, '局部多云');
    if (symbol.contains('cloud')) return (3, '多云');
    if (symbol.contains('fog')) return (45, '有雾');
    if (symbol.contains('drizzle')) return (51, '毛毛雨');
    if (symbol.contains('heavy_rain') || symbol.contains('rain_heavy'))
      return (65, '大雨');
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
