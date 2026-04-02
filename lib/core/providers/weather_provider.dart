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

      // 2. MetService NZ
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
        final detail = _lastMetServiceError;
        state = state.copyWith(
          isLoading: false,
          error: detail != null
              ? 'MetService 请求失败 ($detail)'
              : 'MetService 请求失败，请检查 API Key 和网络',
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

  /// Validates MetOcean API key using Wellington position.
  /// Returns null on success, error string on failure.
  static Future<String?> validateApiKey(String apiKey) async {
    if (apiKey.isEmpty) return 'MetService API Key 未配置';
    try {
      final uri = Uri.https('forecast-v2.metoceanapi.com', '/point/time', {
        'lat': '-41.2865',
        'lon': '174.7762',
        'variables': 'wind.speed.at-10m',
        'repeat': '1',
      });
      final resp = await http
          .get(uri, headers: {'x-api-key': apiKey, 'Accept': 'application/json'})
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode == 200) return null;
      if (resp.statusCode == 401 || resp.statusCode == 403) {
        return 'API Key 无效 (HTTP ${resp.statusCode})';
      }
      return null;
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }

  // Internal: last MetService HTTP error for surfacing to the user.
  String? _lastMetServiceError;

  // ---------------------------------------------------------------------------
  // MetOcean Solutions / MetService NZ point forecast API
  // Docs: https://forecast-docs.metoceanapi.com/swagger-ui/
  // Auth: x-api-key header; key from https://console.metoceanapi.com/
  // ---------------------------------------------------------------------------

  static const _metoceanVars = [
    'wind.speed.at-10m',        // m/s
    'wind.direction.at-10m',    // degrees
    'wind.speed.gust',          // m/s
    'air.temperature.at-2m',    // °C
    'air.pressure.at-sea-level',// hPa
    'air.humidity.at-2m',       // %
    'precipitation.rate',       // mm/h
    'wave.height',              // m
    'wave.period.peak',         // s
    'wave.height.swell',        // m
    'wave.direction.swell',     // degrees
  ];

  Future<WeatherState?> _fetchMetService({
    required double lat,
    required double lon,
    required String apiKey,
  }) async {
    _lastMetServiceError = null;
    try {
      final now = DateTime.now().toUtc();
      final uri = Uri.https('forecast-v2.metoceanapi.com', '/point/time', {
        'lat': lat.toStringAsFixed(4),
        'lon': lon.toStringAsFixed(4),
        'variables': _metoceanVars.join(','),
        'from': now.toIso8601String(),
        'interval': '1h',
        'repeat': '168', // 7 days hourly
      });
      final resp = await http
          .get(uri, headers: {'x-api-key': apiKey, 'Accept': 'application/json'})
          .timeout(const Duration(seconds: 25));

      if (resp.statusCode != 200) {
        final body = resp.body.length > 400 ? resp.body.substring(0, 400) : resp.body;
        _lastMetServiceError = 'HTTP ${resp.statusCode}: $body';
        return null;
      }

      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      // Response: { "dimensions": { "time": { "data": [...] } },
      //             "variables": { "wind.speed.at-10m": { "data": [...] } } }
      final dims = json['dimensions'] as Map<String, dynamic>? ?? {};
      final vars = json['variables'] as Map<String, dynamic>? ?? {};
      final times = ((dims['time'] as Map<String, dynamic>?)?['data'] as List?)
              ?.cast<String>() ?? [];

      List<double?> _v(String name) {
        final v = vars[name] as Map<String, dynamic>?;
        return (v?['data'] as List?)
                ?.map((e) => (e as num?)?.toDouble())
                .toList() ?? [];
      }

      final wsMs   = _v('wind.speed.at-10m');
      final wDir   = _v('wind.direction.at-10m');
      final gustMs = _v('wind.speed.gust');
      final temp   = _v('air.temperature.at-2m');
      final press  = _v('air.pressure.at-sea-level');
      final hum    = _v('air.humidity.at-2m');
      final waveH  = _v('wave.height');
      final waveP  = _v('wave.period.peak');
      final swellH = _v('wave.height.swell');
      final swellD = _v('wave.direction.swell');

      double? toKn(double? ms) => ms != null ? ms * 1.944 : null;

      // Current = index 0
      final curWindKn  = toKn(wsMs.elementAtOrNull(0));
      final curGustKn  = toKn(gustMs.elementAtOrNull(0));
      final curWindDir = wDir.elementAtOrNull(0)?.toInt();
      final curTemp    = temp.elementAtOrNull(0);
      final curWaveH   = waveH.elementAtOrNull(0);
      final curWaveP   = waveP.elementAtOrNull(0);
      final curSwellH  = swellH.elementAtOrNull(0);
      final curSwellD  = swellD.elementAtOrNull(0)?.toInt();
      final curPress   = press.elementAtOrNull(0);
      final curHum     = hum.elementAtOrNull(0);

      // Hourly — next 24h
      final hourly = <HourlyForecast>[];
      for (int i = 0; i < times.length && i < 24; i++) {
        final dt = DateTime.tryParse(times[i]);
        if (dt == null) continue;
        hourly.add(HourlyForecast(
          time: dt,
          temp: temp.elementAtOrNull(i),
          windSpeed: toKn(wsMs.elementAtOrNull(i)),
          windDir: wDir.elementAtOrNull(i)?.toInt(),
          windGust: toKn(gustMs.elementAtOrNull(i)),
          waveHeight: waveH.elementAtOrNull(i),
          wavePeriod: waveP.elementAtOrNull(i),
        ));
      }

      // Daily — aggregate into day buckets
      final Map<String, List<int>> buckets = {};
      for (int i = 0; i < times.length; i++) {
        final dt = DateTime.tryParse(times[i]);
        if (dt == null) continue;
        final key = '${dt.year}-${dt.month.toString().padLeft(2,'0')}-${dt.day.toString().padLeft(2,'0')}';
        buckets.putIfAbsent(key, () => []).add(i);
      }
      final daily = <DailyForecast>[];
      for (final entry in buckets.entries) {
        final idxs = entry.value;
        final dt = DateTime.tryParse(times[idxs.first]);
        if (dt == null) continue;
        double? maxWind, minTemp, maxTemp, maxWave;
        int? midWindDir;
        for (final i in idxs) {
          final w = toKn(wsMs.elementAtOrNull(i));
          if (w != null && (maxWind == null || w > maxWind)) maxWind = w;
          final t = temp.elementAtOrNull(i);
          if (t != null) {
            if (minTemp == null || t < minTemp) minTemp = t;
            if (maxTemp == null || t > maxTemp) maxTemp = t;
          }
          final wh = waveH.elementAtOrNull(i);
          if (wh != null && (maxWave == null || wh > maxWave)) maxWave = wh;
        }
        midWindDir = wDir.elementAtOrNull(idxs[idxs.length ~/ 2])?.toInt();
        daily.add(DailyForecast(
          date: DateTime(dt.year, dt.month, dt.day),
          tempMax: maxTemp,
          tempMin: minTemp,
          windSpeedMax: maxWind,
          windDirDominant: midWindDir,
          waveHeightMax: maxWave,
        ));
      }

      // Derive a simple weather code from wind speed
      final (code, description) = _windToCondition(curWindKn ?? 0);

      return WeatherState(
        temperature: curTemp,
        weatherCode: code,
        condition: conditionFromCode(code),
        windSpeed: curWindKn,
        windDirection: curWindDir,
        windGust: curGustKn,
        waveHeight: curWaveH,
        wavePeriod: curWaveP,
        swellHeight: curSwellH,
        swellDirection: curSwellD,
        pressure: curPress,
        humidity: curHum,
        description: description,
        fetchedAt: DateTime.now(),
        locationLabel: 'MetOcean/MetService NZ',
        hourly: hourly,
        daily: daily,
      );
    } on TimeoutException {
      _lastMetServiceError = '请求超时';
      return null;
    } catch (e) {
      _lastMetServiceError = e.toString();
      return null;
    }
  }

  (int, String) _windToCondition(double windKn) {
    if (windKn >= 48) return (95, '烈风');
    if (windKn >= 34) return (65, '强风');
    if (windKn >= 22) return (55, '中等风力');
    if (windKn >= 11) return (3,  '微风');
    return (1, '平静');
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
