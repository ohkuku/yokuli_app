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

      // Fetch tides + reverse geocoding in parallel (both optional)
      final tidesF = settings.worldTidesApiKey.isNotEmpty
          ? _fetchTides(lat: pos.latitude, lon: pos.longitude, apiKey: settings.worldTidesApiKey)
          : Future.value(const <TideEntry>[]);
      final geoF = _reverseGeocode(pos.latitude, pos.longitude);
      final List<dynamic> aux = await Future.wait([tidesF, geoF]);
      final tides     = aux[0] as List<TideEntry>;
      final geoLabel  = aux[1] as String?;

      state = result.copyWith(
        isLoading: false,
        error: null,
        tides: tides,
        locationLabel: geoLabel ?? result.locationLabel,
      );

      // Fire-and-forget: fetch regional grid for wind map (doesn't block UI)
      _fetchWindGrid(
        lat: pos.latitude,
        lon: pos.longitude,
        apiKey: settings.metServiceApiKey,
        from: _isoHour(DateTime.now().toUtc()),
      ).then((grid) {
        if (grid.isNotEmpty) {
          state = state.copyWith(windGrid: grid);
        }
      // ignore: avoid_catches_without_on_clauses
      }).catchError((_) {});

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
      final now = DateTime.now().toUtc();
      final from = '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}T00:00:00Z';
      final resp = await http.post(
        Uri.parse('https://forecast-v2.metoceanapi.com/point/time'),
        headers: {'x-api-key': apiKey, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'points': [{'lat': -41.2865, 'lon': 174.7762}],
          'variables': ['wind.speed.at-10m'],
          'time': {'from': from, 'interval': '1h', 'repeat': 1},
        }),
      ).timeout(const Duration(seconds: 12));
      if (resp.statusCode == 200) return null;
      if (resp.statusCode == 401 || resp.statusCode == 403) {
        return 'API Key 无效 (HTTP ${resp.statusCode})';
      }
      return null;
    } on TimeoutException { return null; }
    catch (_) { return null; }
  }

  // Internal: last MetService HTTP error for surfacing to the user.
  String? _lastMetServiceError;

  // ---------------------------------------------------------------------------
  // MetOcean Solutions / MetService NZ — POST /point/time
  // Docs:  https://forecast-docs.metoceanapi.com/swagger-ui/
  // Auth:  x-api-key header
  // Notes: temperature returned in Kelvin (subtract 273.15 → °C)
  //        POST body: { points, variables, time:{from,interval,repeat} }
  // ---------------------------------------------------------------------------

  static const _metoceanVars = [
    'wind.speed.at-10m',         // m/s  → ×1.944 knots
    'wind.direction.at-10m',     // degrees
    'air.temperature.at-2m',     // Kelvin → −273.15 °C
    'air.pressure.at-sea-level', // hPa
    'air.humidity.at-2m',        // %
    'wave.height',               // m
    'wave.period.peak',          // s
    'precipitation.rate',        // mm/h — confirmed in official examples
    'cloud.cover',               // 0–1 fraction — confirmed in official examples
  ];

  // Optional variables tried after the main request — failure does not block.
  // wind.speed.gust.at-10m is the best candidate by naming convention
  // (mirrors wind.speed.at-10m exactly).
  static const _metoceanOptional = [
    'wind.speed.gust.at-10m',   // best candidate: matches naming convention
    'wind.speed.gust',           // second candidate: shorthand alias
    'wind.gust.at-10m',          // third candidate: alternate noun structure
  ];

  /// One-shot variable probe: tests every candidate variable against the real
  /// API and prints VALID / INVALID to the debug console.  Call from a dev
  /// button or integration test.  Never shipped in production flows.
  static Future<void> probeVariables(String apiKey) async {
    const candidates = [
      'wind.speed.at-10m', 'wind.direction.at-10m',
      'wind.speed.gust', 'wind.speed.gust.at-10m',
      'air.temperature.at-2m', 'air.pressure.at-sea-level',
      'air.humidity.at-2m', 'relative.humidity.at-2m',
      'wave.height', 'wave.period', 'wave.period.peak',
      'wave.period.above-8s.peak', 'wave.period.below-8s.peak',
      'wave.height.swell', 'wave.direction.peak',
      'precipitation.rate', 'cloud.cover',
    ];
    for (final v in candidates) {
      try {
        final r = await http.post(
          Uri.parse('https://forecast-v2.metoceanapi.com/point/time'),
          headers: {'x-api-key': apiKey, 'Content-Type': 'application/json'},
          body: jsonEncode({
            'points': [{'lat': -41.2865, 'lon': 174.7762}],
            'variables': [v],
            'time': {'from': '2026-04-03T00:00:00Z', 'interval': '1h', 'repeat': 1},
          }),
        ).timeout(const Duration(seconds: 10));
        // ignore: avoid_print
        print('[MetOcean probe] ${r.statusCode == 200 ? "✓ VALID  " : "✗ INVALID"} $v  ${r.statusCode != 200 ? r.body.substring(0, r.body.length.clamp(0, 120)) : ""}');
      } catch (e) {
        // ignore: avoid_print
        print('[MetOcean probe] ? ERROR   $v  $e');
      }
    }
  }

  Future<WeatherState?> _fetchMetService({
    required double lat,
    required double lon,
    required String apiKey,
  }) async {
    _lastMetServiceError = null;
    try {
      final now = DateTime.now().toUtc();
      // Round to nearest hour to avoid sub-second format issues
      final from = '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}T${now.hour.toString().padLeft(2,'0')}:00:00Z';

      final resp = await http.post(
        Uri.parse('https://forecast-v2.metoceanapi.com/point/time'),
        headers: {
          'x-api-key': apiKey,
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'points': [{'lat': lat, 'lon': lon}],
          'variables': _metoceanVars,
          'time': {'from': from, 'interval': '1h', 'repeat': 168},
        }),
      ).timeout(const Duration(seconds: 25));

      if (resp.statusCode != 200) {
        final body = resp.body.length > 400 ? resp.body.substring(0, 400) : resp.body;
        _lastMetServiceError = 'HTTP ${resp.statusCode}: $body';
        return null;
      }

      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final dims = json['dimensions'] as Map<String, dynamic>? ?? {};
      final vars = json['variables'] as Map<String, dynamic>? ?? {};

      // time array — ISO strings
      final times = ((dims['time'] as Map<String, dynamic>?)?['data'] as List?)
              ?.map((e) => e.toString()).toList() ?? [];

      // Extract variable data, applying noData mask
      List<double?> _vFrom(Map<String, dynamic> v) {
        final data   = v['data']   as List? ?? [];
        final noData = v['noData'] as List? ?? [];
        return List.generate(data.length, (i) {
          if ((noData.elementAtOrNull(i) as num? ?? 0) != 0) return null;
          final e = data[i];
          return e is num ? e.toDouble() : null;
        });
      }
      List<double?> _v(String name) {
        final v = vars[name] as Map<String, dynamic>?;
        if (v == null) return [];
        return _vFrom(v);
      }

      double? toKn(double? ms)     => ms != null ? ms * 1.944 : null;
      double? toC(double? k)       => k  != null ? k  - 273.15 : null;

      final wsMs  = _v('wind.speed.at-10m');
      final wDir  = _v('wind.direction.at-10m');
      final tempK = _v('air.temperature.at-2m');
      final press = _v('air.pressure.at-sea-level');
      final hum   = _v('air.humidity.at-2m');
      final waveH = _v('wave.height');
      final waveP = _v('wave.period.peak');
      final precip = _v('precipitation.rate');
      final cloudFrac = _v('cloud.cover');

      // Try optional variables (gust) — one at a time, silently ignore 400.
      List<double?> gustMs = [];
      for (final candidate in _metoceanOptional) {
        try {
          final gr = await http.post(
            Uri.parse('https://forecast-v2.metoceanapi.com/point/time'),
            headers: {'x-api-key': apiKey, 'Content-Type': 'application/json'},
            body: jsonEncode({
              'points': [{'lat': lat, 'lon': lon}],
              'variables': [candidate],
              'time': {'from': from, 'interval': '1h', 'repeat': 168},
            }),
          ).timeout(const Duration(seconds: 10));
          if (gr.statusCode == 200) {
            final gj = jsonDecode(gr.body) as Map<String, dynamic>;
            final gv = (gj['variables'] as Map<String, dynamic>?)?[candidate];
            if (gv != null) {
              gustMs = _vFrom(gv);
              // ignore: avoid_print
              print('[MetOcean] gust variable found: $candidate');
              break;
            }
          }
        } catch (_) {}
      }

      // Current = index 0
      final curWindKn  = toKn(wsMs.elementAtOrNull(0));
      final curGustKn  = toKn(gustMs.elementAtOrNull(0));
      final curWindDir = wDir.elementAtOrNull(0)?.toInt();
      final curTemp    = toC(tempK.elementAtOrNull(0));
      final curWaveH   = waveH.elementAtOrNull(0);
      final curWaveP   = waveP.elementAtOrNull(0);
      final curPress   = press.elementAtOrNull(0);
      final curHum     = hum.elementAtOrNull(0);
      final curPrecip  = precip.elementAtOrNull(0);
      final curCloud   = cloudFrac.elementAtOrNull(0);

      // Derived: dew point (°C) — Magnus approximation ±1 °C
      final curDewPt = (curTemp != null && curHum != null)
          ? curTemp - (100.0 - curHum) / 5.0
          : null;

      // Pressure trend: compare forecast 3h ahead vs now
      // Negative = falling (gale risk if < −6 hPa/3h), positive = rising
      final p3h         = press.elementAtOrNull(3);
      final pressureTrend = (curPress != null && p3h != null)
          ? p3h - curPress
          : null;

      // Hourly — next 24h
      final hourly = <HourlyForecast>[];
      for (int i = 0; i < times.length && i < 24; i++) {
        final dt = DateTime.tryParse(times[i]);
        if (dt == null) continue;
        hourly.add(HourlyForecast(
          time: dt,
          temp: toC(tempK.elementAtOrNull(i)),
          windSpeed: toKn(wsMs.elementAtOrNull(i)),
          windDir: wDir.elementAtOrNull(i)?.toInt(),
          windGust: toKn(gustMs.elementAtOrNull(i)),
          waveHeight: waveH.elementAtOrNull(i),
          wavePeriod: waveP.elementAtOrNull(i),
          precip: precip.elementAtOrNull(i),
          pressure: press.elementAtOrNull(i),
        ));
      }

      // Daily — aggregate hourly into day buckets
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
          final t = toC(tempK.elementAtOrNull(i));
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

      // Derive weather code from cloud cover + precip, falling back to wind.
      final (code, description) = _deriveCondition(
        windKn: curWindKn ?? 0,
        cloudCover: curCloud,
        precipRate: curPrecip,
      );

      return WeatherState(
        temperature: curTemp,
        weatherCode: code,
        condition: conditionFromCode(code),
        windSpeed: curWindKn,
        windDirection: curWindDir,
        windGust: curGustKn,
        waveHeight: curWaveH,
        wavePeriod: curWaveP,
        pressure: curPress,
        humidity: curHum,
        dewPoint: curDewPt,
        pressureTrend: pressureTrend,
        cloudCover: curCloud,
        precipitation: curPrecip,
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

  /// Derive WMO-style weather code and description from cloud cover,
  /// precipitation rate, and wind speed.
  (int, String) _deriveCondition({
    required double windKn,
    double? cloudCover, // 0.0–1.0 fraction
    double? precipRate, // mm/h
  }) {
    // Precipitation takes priority
    if (precipRate != null && precipRate > 4.0) return (65, '中到大雨');
    if (precipRate != null && precipRate > 0.5) return (61, '小雨');
    if (precipRate != null && precipRate > 0.1) return (51, '毛毛雨');

    // Cloud cover
    final cc = cloudCover ?? 0.0;
    final isOvercast = cc > 0.85;
    final isMostlyCloudy = cc > 0.60;
    final isClear = cc < 0.15;

    // Storm wind overrides sky condition
    if (windKn >= 48) return (95, isOvercast ? '烈风暴雨' : '烈风');
    if (windKn >= 34) return (65, isOvercast ? '强风阵雨' : '强风');
    if (windKn >= 22) return (55, isMostlyCloudy ? '多云中等风力' : '中等风力');

    if (isOvercast)    return (3, '阴天');
    if (isMostlyCloudy) return (2, '多云');
    if (isClear)       return (0, '晴朗');
    return (1, '基本晴朗');
  }

  // --------------------------------------------------------------------------
  // ISO-8601 hour string helper
  // --------------------------------------------------------------------------

  static String _isoHour(DateTime utc) =>
      '${utc.year}-${utc.month.toString().padLeft(2, '0')}-${utc.day.toString().padLeft(2, '0')}'
      'T${utc.hour.toString().padLeft(2, '0')}:00:00Z';

  // --------------------------------------------------------------------------
  // Regional wind grid — 7×7 centred on vessel, 0.5° spacing (~55 km)
  // Makes a single MetOcean multi-point request for current conditions.
  // --------------------------------------------------------------------------

  static const _gridN = 7;
  static const _gridStep = 0.5;

  Future<List<WindGridPoint>> _fetchWindGrid({
    required double lat,
    required double lon,
    required String apiKey,
    required String from,
  }) async {
    final half = _gridN ~/ 2;
    final points = <Map<String, dynamic>>[];
    for (int r = 0; r < _gridN; r++) {
      for (int c = 0; c < _gridN; c++) {
        points.add({
          'lat': lat + (r - half) * _gridStep,
          'lon': lon + (c - half) * _gridStep,
        });
      }
    }

    final resp = await http.post(
      Uri.parse('https://forecast-v2.metoceanapi.com/point/time'),
      headers: {'x-api-key': apiKey, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'points': points,
        'variables': [
          'wind.speed.at-10m',
          'wind.direction.at-10m',
          'air.pressure.at-sea-level',
        ],
        'time': {'from': from, 'interval': '1h', 'repeat': 1},
      }),
    ).timeout(const Duration(seconds: 20));

    if (resp.statusCode != 200) {
      // ignore: avoid_print
      print('[WindGrid] HTTP ${resp.statusCode}: ${resp.body.substring(0, resp.body.length.clamp(0, 200))}');
      return [];
    }

    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final vars = body['variables'] as Map<String, dynamic>? ?? {};

    // Debug: print data structure on first call so we can verify format
    // ignore: avoid_print
    final sampleVar = vars.values.firstOrNull as Map<String, dynamic>?;
    if (sampleVar != null) {
      final d = sampleVar['data'];
      // ignore: avoid_print
      print('[WindGrid] data type=${d.runtimeType}  len=${d is List ? (d as List).length : "?"}  first=${d is List && (d as List).isNotEmpty ? d[0].runtimeType : "?"}');
    }

    final speeds = _extractGridVals(vars, 'wind.speed.at-10m', points.length);
    final dirs   = _extractGridVals(vars, 'wind.direction.at-10m', points.length);
    final presses = _extractGridVals(vars, 'air.pressure.at-sea-level', points.length);

    return List.generate(points.length, (i) => WindGridPoint(
      lat: (points[i]['lat'] as num).toDouble(),
      lon: (points[i]['lon'] as num).toDouble(),
      windSpeed: speeds[i] != null ? speeds[i]! * 1.944 : null, // m/s → kn
      windDir: dirs[i]?.toInt(),
      pressure: presses[i],
    ));
  }

  /// Robust multi-point value extractor.
  /// Handles both flat [point0, point1, ...] and nested [[t0],[t0],...] formats.
  static List<double?> _extractGridVals(
      Map<String, dynamic> vars, String name, int n) {
    final v = vars[name] as Map<String, dynamic>?;
    if (v == null) return List.filled(n, null);
    final data   = v['data']   as List? ?? [];
    final noData = v['noData'] as List? ?? [];

    return List.generate(n, (i) {
      if (i >= data.length) return null;
      final entry = data[i];
      // Handle nested [point][time] = [[val]] or flat [val]
      final raw = entry is List ? (entry.isEmpty ? null : entry[0]) : entry;
      // noData mask
      if (i < noData.length) {
        final nd = noData[i];
        final ndv = nd is List ? (nd.isEmpty ? 0 : nd[0]) : nd;
        if ((ndv as num? ?? 0) != 0) return null;
      }
      return raw is num ? raw.toDouble() : null;
    });
  }

  // --------------------------------------------------------------------------
  // Reverse geocoding via OSM Nominatim (free, no key needed)
  // --------------------------------------------------------------------------

  Future<String?> _reverseGeocode(double lat, double lon) async {
    try {
      final resp = await http.get(
        Uri.parse(
          'https://nominatim.openstreetmap.org/reverse'
          '?lat=${lat.toStringAsFixed(4)}&lon=${lon.toStringAsFixed(4)}&format=json',
        ),
        headers: {'User-Agent': 'YokuliApp/1.0 (marine navigation)'},
      ).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return null;
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final addr = body['address'] as Map<String, dynamic>?;
      if (addr != null) {
        final place = addr['suburb'] ?? addr['city'] ?? addr['town'] ??
                      addr['village'] ?? addr['county'] ?? addr['state'];
        final cc = (addr['country_code'] as String?)?.toUpperCase();
        if (place is String && cc != null) return '$place · $cc';
        if (place is String) return place;
      }
      // Fall back to first segment of display_name
      final dn = body['display_name'] as String?;
      return dn?.split(',').first.trim();
    } catch (_) {
      return null;
    }
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
