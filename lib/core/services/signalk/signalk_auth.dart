import 'dart:convert';
import 'package:http/http.dart' as http;

class SignalKAuthException implements Exception {
  final String message;
  const SignalKAuthException(this.message);
  @override
  String toString() => message;
}

class SignalKAuth {
  /// Derives the HTTP base URL from a WebSocket URL.
  /// ws://host:3000/signalk/v1/stream  →  http://host:3000
  static String httpBase(String wsUrl) {
    final s = wsUrl
        .replaceFirst('wss://', 'https://')
        .replaceFirst('ws://', 'http://');
    final idx = s.indexOf('/signalk/');
    return idx >= 0 ? s.substring(0, idx) : s;
  }

  /// POST /signalk/v1/auth/login → returns JWT token on success.
  /// Throws [SignalKAuthException] with a human-readable message on failure.
  static Future<String> login(
    String wsUrl,
    String username,
    String password,
  ) async {
    final base = httpBase(wsUrl);
    final Uri uri;
    try {
      uri = Uri.parse('$base/signalk/v1/auth/login');
    } on FormatException {
      throw SignalKAuthException('Invalid server URL: $wsUrl');
    }

    late http.Response response;
    try {
      response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'username': username, 'password': password}),
          )
          .timeout(const Duration(seconds: 12));
    } catch (e) {
      throw SignalKAuthException('Cannot reach server: $e');
    }

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final token = data['token'] as String?;
      if (token != null && token.isNotEmpty) return token;
      throw const SignalKAuthException('Server returned no token');
    }

    // Parse server error message if available
    String? serverMsg;
    try {
      serverMsg = (jsonDecode(response.body) as Map)['message'] as String?;
    } catch (_) {}
    throw SignalKAuthException(
      serverMsg ?? 'Login failed (HTTP ${response.statusCode})',
    );
  }

  /// Appends token as a query parameter to a WebSocket URL.
  /// Handles existing query params correctly. Returns the original URL unchanged
  /// if it cannot be parsed (malformed input guard).
  static String withToken(String wsUrl, String token) {
    try {
      final uri    = Uri.parse(wsUrl);
      final params = Map<String, String>.from(uri.queryParameters)
        ..['token'] = token;
      return uri.replace(queryParameters: params).toString();
    } on FormatException {
      // Malformed URL — append token as a simple query parameter.
      final sep = wsUrl.contains('?') ? '&' : '?';
      return '$wsUrl${sep}token=${Uri.encodeQueryComponent(token)}';
    }
  }
}
