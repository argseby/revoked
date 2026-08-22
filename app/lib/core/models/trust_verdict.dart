/// Outcome of [DomainVerificationService.verify].
///
/// The states deliberately mirror the four ways the trust chain can
/// finish: fully verified, no DNS proof at all, identity not yet bound
/// to a domain (legacy / pre-DNS), or an active mismatch that indicates
/// spoofing. The UI maps each to a distinct visual and a distinct
/// allow/deny decision.
enum TrustState {
  /// DNS lookup succeeded, fingerprint matched, identity signature
  /// verified against the server root key. Safe to submit.
  verified,

  /// DNS lookup returned no `_revoked.<domain>` TXT record, or the
  /// record is missing the expected `v=revoked1; k=sha256/...` value.
  /// The receiver may proceed with explicit acknowledgment, since this
  /// is the default state for any server that hasn't yet completed DNS
  /// setup.
  dnsMissing,

  /// The identity itself predates DNS verification (no parentSignature)
  /// or the requester didn't declare a domain. Same UX surface as
  /// [dnsMissing] but a different reason worth surfacing.
  unverified,

  /// Trust chain actively contradicts the claim — DNS pin disagrees
  /// with the served pubkey, or the identity signature doesn't verify.
  /// Submission must be blocked; this almost always means spoofing.
  spoofed,

  /// Every signature checks out and the issuing server has withdrawn the
  /// identity anyway. This is the one state a certificate cannot express:
  /// the leaf is good for ten years and its parentSignature never expires,
  /// so a holder removed from the workspace goes on proving what they
  /// proved on their first day. Blocked like [spoofed], but for the
  /// opposite reason — nothing was forged, the vouching simply stopped.
  revoked,
}

class TrustVerdict {
  final TrustState state;
  final String domain;
  final String reason;
  final String? rootFingerprint;
  final String? identityFingerprint;

  const TrustVerdict._({
    required this.state,
    required this.domain,
    required this.reason,
    this.rootFingerprint,
    this.identityFingerprint,
  });

  factory TrustVerdict.verified({
    required String domain,
    required String rootFingerprint,
    required String identityFingerprint,
  }) => TrustVerdict._(
    state: TrustState.verified,
    domain: domain,
    reason: 'DNS-verified — root key on $domain matches the published TXT.',
    rootFingerprint: rootFingerprint,
    identityFingerprint: identityFingerprint,
  );

  factory TrustVerdict.dnsMissing({
    required String domain,
    required String reason,
  }) => TrustVerdict._(
    state: TrustState.dnsMissing,
    domain: domain,
    reason: reason,
  );

  factory TrustVerdict.unverified({
    required String domain,
    required String reason,
  }) => TrustVerdict._(
    state: TrustState.unverified,
    domain: domain,
    reason: reason,
  );

  factory TrustVerdict.spoofed({
    required String domain,
    required String reason,
  }) =>
      TrustVerdict._(state: TrustState.spoofed, domain: domain, reason: reason);

  factory TrustVerdict.revoked({
    required String domain,
    required String reason,
    String? rootFingerprint,
    String? identityFingerprint,
  }) => TrustVerdict._(
    state: TrustState.revoked,
    domain: domain,
    reason: reason,
    rootFingerprint: rootFingerprint,
    identityFingerprint: identityFingerprint,
  );

  /// True when the user should be allowed to submit. Spoofed and revoked
  /// are hard blocks; the other non-verified states are soft and let the
  /// UI ask for explicit confirmation.
  bool get allowsSubmit =>
      state != TrustState.spoofed && state != TrustState.revoked;
}
