/// A part of the app a person chooses to see, mirroring the catalogue in the
/// Go backend's `util/features.go`.
///
/// The keys are known here because screens hang off them; everything the
/// reader sees — labels, descriptions, which permission each needs — comes
/// from `GET /api/features`, so the app never drifts from the server's list.
/// A feature is a display choice, never a boundary: the server enforces the
/// permission whether or not the feature is on.
enum Feature {
  sharing('sharing', 'Sharing', defaultOn: true),
  requests('requests', 'Requests', defaultOn: true),
  attestations('attestations', 'Identities and attestations', defaultOn: true),
  contacts('contacts', 'Contacts', defaultOn: true),
  tools('tools', 'Connected tools', defaultOn: true),
  developer('developer', 'Developer', defaultOn: false);

  const Feature(this.key, this.fallbackLabel, {required this.defaultOn});

  final String key;

  /// What a fresh account sees before it chooses. The catalogue's own
  /// default wins once it has loaded; this only covers the time before.
  final bool defaultOn;

  /// The name shown while the catalogue has not loaded.
  final String fallbackLabel;

  static Feature? fromKey(String? key) {
    for (final f in values) {
      if (f.key == key) return f;
    }
    return null;
  }
}

/// One catalogue entry as the server describes it.
class FeatureInfo {
  final String key;
  final String label;
  final String description;

  /// The permission key the feature is pointless without, or empty.
  final String permission;
  final bool defaultOn;

  const FeatureInfo({
    required this.key,
    required this.label,
    required this.description,
    this.permission = '',
    this.defaultOn = true,
  });

  factory FeatureInfo.fromJson(Map<String, dynamic> json) => FeatureInfo(
    key: json['key'] as String? ?? '',
    label: json['label'] as String? ?? '',
    description: json['description'] as String? ?? '',
    permission: json['permission'] as String? ?? '',
    defaultOn: json['defaultOn'] as bool? ?? true,
  );

  Feature? get feature => Feature.fromKey(key);
}

/// A kind of member an invite can be made for: the permissions it grants and
/// the features it starts them on. The server stores the two lists, never the
/// preset's name.
class FeaturePreset {
  final String key;
  final String label;
  final String description;
  final List<String> permissions;
  final List<String> features;

  const FeaturePreset({
    required this.key,
    required this.label,
    required this.description,
    required this.permissions,
    required this.features,
  });

  factory FeaturePreset.fromJson(Map<String, dynamic> json) => FeaturePreset(
    key: json['key'] as String? ?? '',
    label: json['label'] as String? ?? '',
    description: json['description'] as String? ?? '',
    permissions: _strings(json['permissions']),
    features: _strings(json['features']),
  );
}

List<String> _strings(Object? raw) =>
    ((raw as List<dynamic>?) ?? const []).map((e) => e.toString()).toList();
