/// Someone asking for an attestation about one of their identities: which
/// kind, which claims, and the identity it should be bound to.
///
/// It travels as `revoked://attest?type=…&claims=…&for=…&name=…` and fills
/// in the attester's form. Everything in it is the asker's wish, not a fact:
/// the attester still decides every value, and the fingerprint only means the
/// offer can be accepted by that identity alone.
class AttestationAsk {
  final String type;
  final List<String> claims;
  final String fingerprint;

  /// What the asker calls themselves. Unverified, so it only ever labels.
  final String name;

  const AttestationAsk({
    required this.type,
    required this.claims,
    required this.fingerprint,
    this.name = '',
  });

  static final _type = RegExp(r'^[\x21-\x7e]{1,255}$');
  static final _claim = RegExp(r'^[A-Za-z][A-Za-z0-9_]{0,63}$');
  static final _fingerprint = RegExp(r'^[0-9a-f]{64}$');

  /// Claim names as a person types them: separated by commas or spaces.
  static List<String> splitClaims(String raw) => raw
      .split(RegExp(r'[,\s]+'))
      .map((c) => c.trim())
      .where((c) => c.isNotEmpty)
      .toSet()
      .toList();

  /// Null unless every part is well formed: a link that is half right fills
  /// in nothing rather than something wrong.
  static AttestationAsk? fromQuery(Map<String, String> q) {
    final type = (q['type'] ?? '').trim();
    final fingerprint = (q['for'] ?? '').trim().toLowerCase();
    final claims = splitClaims(q['claims'] ?? '');
    if (!_type.hasMatch(type) || !_fingerprint.hasMatch(fingerprint)) {
      return null;
    }
    if (claims.length > 50 || !claims.every(_claim.hasMatch)) return null;
    final name = (q['name'] ?? '').trim();
    return AttestationAsk(
      type: type,
      claims: claims,
      fingerprint: fingerprint,
      name: name.length > 100 ? name.substring(0, 100) : name,
    );
  }

  Map<String, String> toQuery() => {
    'type': type,
    if (claims.isNotEmpty) 'claims': claims.join(','),
    'for': fingerprint,
    if (name.isNotEmpty) 'name': name,
  };

  String get link => Uri(
    scheme: 'revoked',
    host: 'attest',
    queryParameters: toQuery(),
  ).toString();
}
