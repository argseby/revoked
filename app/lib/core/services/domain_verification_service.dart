import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:revoked_app/core/models/trust_verdict.dart';
import 'package:revoked_app/core/services/crypto_service.dart';

/// Verifies a remote server's domain claim end-to-end.
///
/// The trust chain we walk, in order:
///
///   1. Pull the TXT record at `_revoked.<domain>` via DNS-over-HTTPS
///      (Cloudflare 1.1.1.1). DoH is used instead of raw DNS so this
///      works from mobile/web without platform-specific resolver code,
///      and the DoH endpoint is itself authenticated by TLS.
///   2. Fetch `https://<domain>/api/server` to obtain the server's
///      claimed root public key + a freshly-signed assertion.
///   3. Compute the SHA-256 fingerprint of the fetched pubkey PEM and
///      confirm it matches the fingerprint pinned in the TXT record.
///      A mismatch here is what catches a spoofed server: the attacker
///      can serve their own /api/server but cannot rewrite the victim's
///      DNS.
///   4. Verify the identity's `parentSignature` (delivered in the
///      request probe) against the fetched root pubkey. This is what
///      binds a specific identity to the verified domain — without this
///      step an attacker who briefly compromised the victim server
///      could replay an old identity record.
///
/// Each step's outcome is surfaced in the returned [TrustVerdict] so the
/// UI can render the *reason* an identity is or isn't trusted, not just
/// a binary verdict.
class DomainVerificationService {
  /// Tried in order. A single resolver is both an availability risk — the
  /// whole trust chain stops when it is unreachable or blocked — and a party
  /// that gets to see every domain anyone verifies.
  static const List<String> _dohEndpoints = [
    'https://cloudflare-dns.com/dns-query',
    'https://dns.google/resolve',
  ];

  /// Every hop in the chain is bounded. Unbounded, a server that accepts the
  /// connection and then stalls leaves the verdict pending forever, and the
  /// submit gate waiting on it with it.
  static const Duration _networkTimeout = Duration(seconds: 8);

  /// TXT records carrying `v=revoked1; k=sha256/<hex>`.
  static final RegExp _txtPattern = RegExp(
    r'v=revoked1;\s*k=sha256/([0-9a-f]{64})',
    caseSensitive: false,
  );

  final http.Client _http;
  final CryptoService _crypto;

  DomainVerificationService({
    http.Client? httpClient,
    required CryptoService crypto,
  }) : _http = httpClient ?? http.Client(),
       _crypto = crypto;

  /// Runs the full verification chain.
  ///
  /// [claimedDomain] is the domain the request probe said it came from.
  /// [identityFingerprint] is the cert fingerprint to verify against the
  /// signature. [parentSignatureHex] is the identity's parentSignature
  /// (hex-encoded as the server emits it). Pass empty string for
  /// pre-DNS identities — the verdict will be [TrustState.unverified].
  Future<TrustVerdict> verify({
    required String claimedDomain,
    required String identityFingerprint,
    required String parentSignatureHex,
  }) async {
    if (claimedDomain.isEmpty) {
      return TrustVerdict.unverified(
        domain: claimedDomain,
        reason:
            'The requester did not declare a domain. No DNS verification '
            'is possible.',
      );
    }
    if (parentSignatureHex.isEmpty) {
      return TrustVerdict.unverified(
        domain: claimedDomain,
        reason:
            'This identity was issued before DNS verification was '
            'enabled on the requester\'s server, so it cannot be '
            'verified against $claimedDomain.',
      );
    }

    final String? dnsFingerprint;
    try {
      dnsFingerprint = await _lookupTxtFingerprint(claimedDomain);
    } on _VerificationError catch (e) {
      return TrustVerdict.dnsMissing(domain: claimedDomain, reason: e.message);
    }
    if (dnsFingerprint == null) {
      return TrustVerdict.dnsMissing(
        domain: claimedDomain,
        reason:
            'No TXT record found at _revoked.$claimedDomain. Either the '
            'operator has not published one or DNS has not propagated.',
      );
    }

    final _ServerInfo info;
    try {
      info = await _fetchServerInfo(claimedDomain);
    } on _VerificationError catch (e) {
      return TrustVerdict.unverified(domain: claimedDomain, reason: e.message);
    }

    final fetchedFingerprint = _crypto.sha256Hex(info.publicKeyPem);
    if (fetchedFingerprint != dnsFingerprint.toLowerCase()) {
      return TrustVerdict.spoofed(
        domain: claimedDomain,
        reason:
            'DNS pins root key $dnsFingerprint but the server at '
            '$claimedDomain is serving a different key '
            '($fetchedFingerprint). This is consistent with a spoofed '
            'or hijacked server — do NOT submit data.',
      );
    }
    if (fetchedFingerprint != info.claimedFingerprint.toLowerCase()) {
      return TrustVerdict.spoofed(
        domain: claimedDomain,
        reason:
            'The server\'s /api/server response is internally '
            'inconsistent: its embedded pubkey does not match the '
            'fingerprint it advertises.',
      );
    }

    final Uint8List sig;
    try {
      sig = _decodeHex(parentSignatureHex);
    } on FormatException {
      return TrustVerdict.spoofed(
        domain: claimedDomain,
        reason: 'The identity\'s parentSignature is not valid hex.',
      );
    }
    final signatureValid = _crypto.verifySignature(
      publicKeyPem: info.publicKeyPem,
      message: identityFingerprint,
      signatureBytes: sig,
    );
    if (!signatureValid) {
      return TrustVerdict.spoofed(
        domain: claimedDomain,
        reason:
            'The identity claims to be from $claimedDomain but its '
            'signature does not verify under that server\'s root key.',
      );
    }

    return TrustVerdict.verified(
      domain: claimedDomain,
      rootFingerprint: fetchedFingerprint,
      identityFingerprint: identityFingerprint,
    );
  }

  /// Looks up `_revoked.<domain>` via DoH and returns the embedded
  /// fingerprint. Returns null when the record genuinely does not
  /// exist; throws [_VerificationError] when the DNS lookup itself
  /// fails (network down, blocked, etc.) — the caller renders those
  /// two outcomes differently.
  Future<String?> _lookupTxtFingerprint(String domain) async {
    _VerificationError? lastFailure;
    for (final endpoint in _dohEndpoints) {
      try {
        return await _lookupVia(endpoint, domain);
      } on _VerificationError catch (e) {
        lastFailure = e;
      }
    }
    throw lastFailure ?? _VerificationError('DNS lookup failed.');
  }

  Future<String?> _lookupVia(String endpoint, String domain) async {
    final uri = Uri.parse('$endpoint?name=_revoked.$domain&type=TXT');
    final http.Response resp;
    try {
      resp = await _http
          .get(uri, headers: const {'accept': 'application/dns-json'})
          .timeout(_networkTimeout);
    } catch (e) {
      throw _VerificationError('DNS lookup failed: $e');
    }
    if (resp.statusCode != 200) {
      throw _VerificationError('DNS lookup returned HTTP ${resp.statusCode}.');
    }
    // A captive portal or intercepting proxy answers 200 with HTML. Decoding
    // that outside the guard threw straight past every verdict path and left
    // the caller with no verdict at all.
    final Map<String, dynamic> body;
    try {
      body = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      throw _VerificationError(
        'DNS lookup returned something other than a DNS answer. A captive '
        'portal or filtering proxy may be intercepting the request.',
      );
    }
    final answers = (body['Answer'] as List?) ?? const [];
    for (final raw in answers) {
      final ans = raw as Map<String, dynamic>;
      // DoH returns TXT values wrapped in quotes; strip them.
      final data = (ans['data'] as String?)?.replaceAll('"', '') ?? '';
      final match = _txtPattern.firstMatch(data);
      if (match != null) {
        return match.group(1)!.toLowerCase();
      }
    }
    return null;
  }

  Future<_ServerInfo> _fetchServerInfo(String domain) async {
    final uri = Uri.parse('https://$domain/api/server');
    final http.Response resp;
    try {
      resp = await _http.get(uri).timeout(_networkTimeout);
    } catch (e) {
      throw _VerificationError(
        'Could not reach https://$domain/api/server: $e',
      );
    }
    if (resp.statusCode != 200) {
      throw _VerificationError(
        'https://$domain/api/server returned HTTP ${resp.statusCode}.',
      );
    }
    final Map<String, dynamic> body;
    try {
      body = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      throw _VerificationError(
        'https://$domain/api/server did not return JSON.',
      );
    }
    final pem = body['publicKey'] as String?;
    final fp = body['fingerprint'] as String?;
    if (pem == null || pem.isEmpty || fp == null || fp.isEmpty) {
      throw _VerificationError(
        'https://$domain/api/server returned an incomplete response.',
      );
    }
    return _ServerInfo(publicKeyPem: pem, claimedFingerprint: fp);
  }

  Uint8List _decodeHex(String hex) {
    if (hex.length.isOdd) {
      throw const FormatException('hex string has odd length');
    }
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }
}

class _ServerInfo {
  final String publicKeyPem;
  final String claimedFingerprint;
  const _ServerInfo({
    required this.publicKeyPem,
    required this.claimedFingerprint,
  });
}

class _VerificationError implements Exception {
  final String message;
  _VerificationError(this.message);
}
