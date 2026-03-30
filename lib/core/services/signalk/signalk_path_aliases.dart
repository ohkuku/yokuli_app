/// Normalizes variant Signal K paths to canonical forms.
///
/// Some Signal K server implementations (e.g. Victron via venus-signalk) emit
/// non-standard path names for solar charge controller data.  This class maps
/// those variants to the canonical paths used throughout the app so that the
/// rest of the parsing layer only needs to handle one name per measurement.
class SignalKPathAliases {
  SignalKPathAliases._();

  // ---------------------------------------------------------------------------
  // Solar path alias table
  // key   = non-canonical field name  (the part after 'electrical.solar.<id>.')
  // value = canonical field name
  // ---------------------------------------------------------------------------
  static const Map<String, String> _solarFieldAliases = {
    'chargePower': 'outputPower',
    'chargeVoltage': 'outputVoltage',
    'chargeCurrent': 'outputCurrent',
    'panelVoltage': 'inputVoltage',
    'panelCurrent': 'inputCurrent',
    'panelPower': 'inputPower',
    'state': 'chargerState',
    'yieldToday': 'yieldTodayWh',
  };

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Normalizes a full Signal K path to its canonical form.
  ///
  /// Currently handles solar field aliases only.  Returns [null] when the path
  /// is not recognized as a non-canonical alias (i.e. it is already canonical
  /// or simply unknown).
  static String? canonicalize(String path) {
    final solar = extractSolar(path);
    if (solar != null) {
      // Only return a value when the path was actually an alias.
      final field = path.substring('electrical.solar.'.length + solar.id.length + 1);
      if (_solarFieldAliases.containsKey(field)) {
        return solar.canonical;
      }
    }
    return null;
  }

  /// Extracts the controller ID and returns the canonical path for any
  /// 'electrical.solar.<id>.<field>' path (canonical or alias).
  ///
  /// Example:
  ///   'electrical.solar.abc123.panelVoltage'
  ///     -> (id: 'abc123', canonical: 'electrical.solar.abc123.inputVoltage')
  ///
  /// Returns [null] if [path] does not match the expected prefix structure.
  static ({String id, String canonical})? extractSolar(String path) {
    const prefix = 'electrical.solar.';
    if (!path.startsWith(prefix)) return null;

    final remainder = path.substring(prefix.length); // '<id>.<field...>'
    final dotIndex = remainder.indexOf('.');
    if (dotIndex < 1) return null;

    final id = remainder.substring(0, dotIndex);
    final field = remainder.substring(dotIndex + 1);

    // Map alias -> canonical field, or keep as-is if already canonical.
    final canonicalField = _solarFieldAliases[field] ?? field;
    return (id: id, canonical: '$prefix$id.$canonicalField');
  }

  /// Extracts the battery ID and returns the canonical path for any
  /// 'electrical.batteries.<id>.<field...>' path.
  ///
  /// Battery paths don't currently have aliases; this helper exists for
  /// symmetry and for callers that need the id without manual splitting.
  ///
  /// Returns [null] if [path] does not start with 'electrical.batteries.'.
  static ({String id, String canonical})? extractBattery(String path) {
    const prefix = 'electrical.batteries.';
    if (!path.startsWith(prefix)) return null;

    final remainder = path.substring(prefix.length);
    final dotIndex = remainder.indexOf('.');
    if (dotIndex < 1) return null;

    final id = remainder.substring(0, dotIndex);
    // Battery paths are already canonical.
    return (id: id, canonical: path);
  }

  /// Extracts the AIS vessel context string and the field path from a full
  /// Signal K path of the form 'vessels.<context>.<field...>'.
  ///
  /// Example:
  ///   'vessels.urn:mrn:imo:mmsi:123456789.navigation.position'
  ///     -> (context: 'vessels.urn:mrn:imo:mmsi:123456789',
  ///         field:   'navigation.position')
  ///
  /// Returns [null] if [path] does not match the expected structure.
  static ({String context, String field})? extractAisVessel(String path) {
    const prefix = 'vessels.';
    if (!path.startsWith(prefix)) return null;

    final remainder = path.substring(prefix.length);

    // The context identifier can itself contain dots (URN syntax), so we
    // locate the boundary by finding the first segment that looks like a
    // field name.  In practice Signal K vessel URNs use the form
    // 'urn:mrn:imo:mmsi:<digits>' which contains colons, not dots.
    // The vessel id segment therefore ends at the first '.' character.
    final dotIndex = remainder.indexOf('.');
    if (dotIndex < 1) return null;

    final vesselId = remainder.substring(0, dotIndex);
    final field = remainder.substring(dotIndex + 1);
    if (field.isEmpty) return null;

    return (context: '$prefix$vesselId', field: field);
  }

  /// Returns the canonical field name for a solar field, or the original
  /// field name if no alias mapping exists.
  static String canonicalizeSolarField(String field) =>
      _solarFieldAliases[field] ?? field;
}
