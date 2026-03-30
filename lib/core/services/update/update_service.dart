import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

const _owner = 'ohkuku';
const _repo = 'yokuli_app';

class UpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String releaseUrl;
  final String? apkUrl;      // direct APK asset URL, null if not found
  final String releaseNotes;
  final bool hasUpdate;

  const UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseUrl,
    required this.apkUrl,
    required this.releaseNotes,
    required this.hasUpdate,
  });
}

class UpdateService {
  /// Checks GitHub Releases for a newer version.
  /// Returns null if on web, if up-to-date, or if the check fails.
  static Future<UpdateInfo?> checkForUpdate() async {
    if (kIsWeb) return null; // web updates itself on page reload

    try {
      final info = await PackageInfo.fromPlatform();
      final current = _normalizeVersion(info.version);

      final uri = Uri.parse(
        'https://api.github.com/repos/$_owner/$_repo/releases/latest',
      );
      final response = await http
          .get(uri, headers: {'Accept': 'application/vnd.github+json'})
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final tagName = (json['tag_name'] as String? ?? '').replaceFirst('v', '');
      final latest = _normalizeVersion(tagName);
      final releaseUrl = json['html_url'] as String? ?? '';
      final body = json['body'] as String? ?? '';

      // Find APK asset in release assets
      String? apkUrl;
      final assets = json['assets'] as List<dynamic>? ?? [];
      for (final asset in assets) {
        final name = asset['name'] as String? ?? '';
        if (name.endsWith('.apk')) {
          apkUrl = asset['browser_download_url'] as String?;
          break;
        }
      }

      final hasUpdate = _isNewer(latest, current);

      if (!hasUpdate) return null;

      return UpdateInfo(
        currentVersion: current,
        latestVersion: latest,
        releaseUrl: releaseUrl,
        apkUrl: apkUrl,
        releaseNotes: _trimNotes(body),
        hasUpdate: true,
      );
    } catch (_) {
      return null; // network error, version parse error, etc.
    }
  }

  static String _normalizeVersion(String v) {
    // Strip build metadata, keep only major.minor.patch
    return v.split('+').first.trim();
  }

  /// Returns true if [a] is strictly newer than [b].
  static bool _isNewer(String a, String b) {
    final pa = _parts(a);
    final pb = _parts(b);
    for (var i = 0; i < 3; i++) {
      if (pa[i] > pb[i]) return true;
      if (pa[i] < pb[i]) return false;
    }
    return false;
  }

  static List<int> _parts(String v) {
    final segments = v.split('.');
    return List.generate(3, (i) => i < segments.length ? int.tryParse(segments[i]) ?? 0 : 0);
  }

  static String _trimNotes(String notes) {
    // Keep first 800 chars to avoid overflow in dialog
    if (notes.length > 800) return '${notes.substring(0, 797)}…';
    return notes;
  }
}
