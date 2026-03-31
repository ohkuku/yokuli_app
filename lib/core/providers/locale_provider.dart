import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/strings.dart';
import 'lan_broadcast.dart';

const _kLangKey = 'app_language';

class LocaleNotifier extends Notifier<String> {
  @override
  String build() => 'en'; // default; will be overridden in initState

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kLangKey);
    if (saved != null) state = saved;
  }

  Future<void> setLanguage(String code) async {
    state = code;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLangKey, code);
    // Broadcast language change to LAN peers
    ref.read(lanBroadcastProvider)?.call({
      'type': 'settings_sync',
      'data': {'language': code},
    });
  }

  /// Apply language received from a LAN peer (no re-broadcast).
  Future<void> applyRemote(String code) async {
    state = code;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLangKey, code);
  }
}

final localeProvider = NotifierProvider<LocaleNotifier, String>(
  LocaleNotifier.new,
);

/// Convenience: current locale as a Flutter Locale object.
final flutterLocaleProvider = Provider<Locale>((ref) {
  return Locale(ref.watch(localeProvider));
});

/// The active string table.
final stringsProvider = Provider<S>((ref) {
  return S.of(ref.watch(localeProvider));
});
