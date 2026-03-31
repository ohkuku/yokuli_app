import '../../../core/models/mob_trigger_rule.dart';

/// Evaluates incoming SignalK delta messages against a list of [MobTriggerRule]s.
///
/// This service is stateless — rules are pushed in via [updateRules] and deltas
/// are evaluated lazily in [onDelta].  When a rule matches, [onRuleMatched] is
/// called with the matching rule (fired at most once per delta).
///
/// **Integration:**
/// Wire [onDelta] to `SignalKClient.onRawDelta` in startup so that every raw
/// SK delta is evaluated here before the parser applies it to [VesselState].
class MobWatcherService {
  List<MobTriggerRule> _rules = [];

  /// Called when a rule matches an incoming delta.
  void Function(MobTriggerRule rule)? onRuleMatched;

  // ── Public API ──────────────────────────────────────────────────────────────

  void updateRules(List<MobTriggerRule> rules) {
    _rules = rules.where((r) => r.enabled).toList();
  }

  /// Evaluate a raw SignalK delta [json] against enabled rules.
  void onDelta(Map<String, dynamic> json) {
    if (_rules.isEmpty) return;

    final updates = json['updates'] as List<dynamic>?;
    if (updates == null || updates.isEmpty) return;

    for (final rule in _rules) {
      if (_matches(rule, updates)) {
        onRuleMatched?.call(rule);
        return; // fire once per delta
      }
    }
  }

  // ── Rule matchers ───────────────────────────────────────────────────────────

  bool _matches(MobTriggerRule rule, List<dynamic> updates) {
    switch (rule.type) {
      case MobTriggerType.signalkPath:
        return _matchPath(rule.config, updates);
      case MobTriggerType.signalkNotification:
        return _matchNotification(rule.config, updates);
      case MobTriggerType.nmeaSentence:
        return _matchNmea(rule.config, updates);
    }
  }

  // ── signalkPath ─────────────────────────────────────────────────────────────

  bool _matchPath(Map<String, dynamic> config, List<dynamic> updates) {
    final targetPath = config['path'] as String?;
    if (targetPath == null || targetPath.isEmpty) return false;

    final matchState = config['matchStateEquals'] as String?;

    for (final update in updates) {
      final values = (update as Map<String, dynamic>?)?['values'] as List<dynamic>?;
      if (values == null) continue;
      for (final v in values) {
        final item = v as Map<String, dynamic>?;
        if (item == null) continue;
        final path = item['path'] as String?;
        if (path != targetPath) continue;

        // Path matched — check optional state filter
        if (matchState != null) {
          final value = item['value'];
          if (value is Map) {
            if ((value['state'] as String?) == matchState) return true;
          }
        } else {
          return true; // any value on this path = trigger
        }
      }
    }
    return false;
  }

  // ── signalkNotification ─────────────────────────────────────────────────────

  bool _matchNotification(Map<String, dynamic> config, List<dynamic> updates) {
    final pattern = (config['pathPattern'] as String? ?? '').toLowerCase();
    final states = (config['states'] as List<dynamic>?)
        ?.map((s) => s.toString().toLowerCase())
        .toSet() ?? {'emergency', 'alarm'};

    for (final update in updates) {
      final values = (update as Map<String, dynamic>?)?['values'] as List<dynamic>?;
      if (values == null) continue;
      for (final v in values) {
        final item = v as Map<String, dynamic>?;
        if (item == null) continue;
        final path = (item['path'] as String? ?? '').toLowerCase();

        // Path must start with 'notifications.' and contain the pattern
        if (!path.startsWith('notifications.')) continue;
        if (pattern.isNotEmpty && !path.contains(pattern)) continue;

        // Check the state field in the value
        final value = item['value'];
        if (value is Map) {
          final state = (value['state'] as String? ?? '').toLowerCase();
          if (states.contains(state)) return true;
        } else {
          // No state filter configured — any notification on this path triggers
          if (pattern.isEmpty) continue;
          return true;
        }
      }
    }
    return false;
  }

  // ── nmeaSentence ────────────────────────────────────────────────────────────

  bool _matchNmea(Map<String, dynamic> config, List<dynamic> updates) {
    final talkerId = (config['talkerId'] as String? ?? '').toUpperCase();
    final sentenceType = (config['sentenceType'] as String? ?? '').toUpperCase();
    final keyword = (config['keyword'] as String? ?? '').toUpperCase();

    if (sentenceType.isEmpty) return false;

    // SK exposes raw NMEA via path 'sentences' with the raw string as value
    for (final update in updates) {
      final values = (update as Map<String, dynamic>?)?['values'] as List<dynamic>?;
      if (values == null) continue;
      for (final v in values) {
        final item = v as Map<String, dynamic>?;
        if (item == null) continue;
        final path = item['path'] as String?;
        if (path != 'sentences') continue;

        final raw = (item['value'] as String? ?? '').toUpperCase();
        if (!raw.startsWith('\$')) continue;

        // NMEA format: $TTSSS,... where TT = talker (2 chars), SSS = type (3 chars)
        // Minimum: $TTSSS,
        if (raw.length < 7) continue;
        final header = raw.substring(1, 6); // e.g. 'AIMOB'
        final parsedTalker = header.substring(0, 2);
        final parsedType = header.substring(2, 5);

        if (parsedType != sentenceType) continue;
        if (talkerId.isNotEmpty && parsedTalker != talkerId) continue;
        if (keyword.isNotEmpty && !raw.contains(keyword)) continue;

        return true;
      }
    }
    return false;
  }
}
