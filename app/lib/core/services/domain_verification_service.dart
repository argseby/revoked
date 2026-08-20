import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
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
  /// Per hop. A healthy check finishes in about a tenth of a second, so
  /// this only ever bounds a broken one - and it bounds a wait a person
  /// is sitting through, not a background job.
  static const Duration _networkTimeout = Duration(seconds: 5);

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

  /// Verdicts already reached, by domain+fingerprint, surviving restarts.
  ///
  /// A cached verdict is a **hint for rendering, never the answer to
  /// submit on**. Callers show it immediately so the screen is not blank,
  /// and always re-run [verify] behind it; the submit gate waits on that
  /// fresh result. Otherwise a rotated or compromised key - or a verdict
  /// obtained once through an intercepting proxy - would keep vouching
  /// for a server long after it stopped deserving it.
  final Map<String, _CachedVerdict> _cache = {};

  /// How long a stored verdict may be shown before it is treated as
  /// unknown. Short enough that a key rotation surfaces within a day even
  /// if revalidation never gets a chance to run.
  static const cacheTtl = Duration(hours: 24);

  static const _prefsKey = 'trust_verdict_cache';

  /// Fetches in flight, so two callers for one domain share one round-trip.
  /// Entries are dropped as they complete - this dedupes concurrent work, it
  /// does not cache results.
  final Map<String, Future<String?>> _pinInFlight = {};
  final Map<String, Future<_ServerInfo>> _infoInFlight = {};

  Future<T> _shared<T>(
    Map<String, Future<T>> inFlight,
    String domain,
    Future<T> Function() start,
  ) {
    final existing = inFlight[domain];
    if (existing != null) return existing;
    final future = start();
    inFlight[domain] = future;
    void drop() {
      if (identical(inFlight[domain], future)) inFlight.remove(domain);
    }

    // then(onError:) rather than whenComplete: whenComplete re-raises
    // into a derived future nobody listens to, which reports as an
    // unhandled async error even though every real caller catches.
    future.then<void>((_) => drop(), onError: (Object _) => drop());
    return future;
  }

  /// Starts the two network hops for [domain] before anything needs them.
  ///
  /// The full check cannot run until the probe returns the requester's
  /// fingerprint, but neither hop depends on it - and a link already names
  /// the server it lives on. Calling this as the screen opens overlaps the
  /// DNS work with the probe instead of queueing behind it.
  void prewarm(String domain) {
    if (domain.isEmpty) return;
    // Errors are re-raised to whoever awaits the real check; swallow them
    // here so a prewarm nobody consumed is not an unhandled async error.
    _shared(
      _pinInFlight,
      domain,
      () => _lookupTxtFingerprint(domain),
    ).catchError((Object _) => null);
    _shared(
      _infoInFlight,
      domain,
      () => _fetchServerInfo(domain),
    ).catchError((Object _) => _ServerInfo.empty);
  }

  /// Reads stored verdicts once at startup. Failure is not an error - an
  /// unreadable cache simply means every check runs fresh.
  Future<void> loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final now = DateTime.now();
      decoded.forEach((key, value) {
        final entry = _CachedVerdict.fromJson(value as Map<String, dynamic>);
        if (entry != null && now.difference(entry.checkedAt) < cacheTtl) {
          _cache[key] = entry;
        }
      });
    } catch (_) {
      _cache.clear();
    }
  }

  /// The stored verdict for this pair, if one is still within [cacheTtl].
  /// Synchronous so a screen can render it on its first frame.
  TrustVerdict? cachedVerdict({
    required String claimedDomain,
    required String identityFingerprint,
  }) {
    final entry = _cache['$claimedDomain|$identityFingerprint'];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.checkedAt) >= cacheTtl) return null;
    return entry.verdict;
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode(_cache.map((k, v) => MapEntry(k, v.toJson()))),
      );
    } catch (_) {
      // A cache that cannot be written costs a re-check, nothing more.
    }
  }

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
    // No cache read here: verify() is the fresh path callers gate on.
    // Rendering from cache is [cachedVerdict], chosen explicitly.
    final key = '$claimedDomain|$identityFingerprint';
    final verdict = await _verifyWithDeadline(
      claimedDomain: claimedDomain,
      identityFingerprint: identityFingerprint,
      parentSignatureHex: parentSignatureHex,
    );
    // Only a conclusive answer is worth keeping; a transient network
    // failure must not pin "unverified" until the TTL expires.
    if (verdict.state == TrustState.verified ||
        verdict.state == TrustState.spoofed) {
      _cache[key] = _CachedVerdict(verdict, DateTime.now());
      // Awaited: an unflushed write is lost if the app closes right
      // after, which is exactly when a verdict is worth keeping. The
      // write is a few milliseconds against a network walk.
      await _persist();
    } else {
      // A previously good verdict that no longer holds must not linger.
      if (_cache.remove(key) != null) await _persist();
    }
    return verdict;
  }

  /// The whole walk is bounded, not just its individual hops: two 8-second
  /// timeouts plus signature work could otherwise hold the UI on "Checking…"
  /// far longer than anyone waits. A deadline reached is an unverified
  /// identity, which the caller already knows how to render.
  /// Backstop above the per-hop budget: the hops normally surface their
  /// own timeouts first, and this only catches a walk that stalls
  /// somewhere else.
  static const _overallDeadline = Duration(seconds: 8);

  Future<TrustVerdict> _verifyWithDeadline({
    required String claimedDomain,
    required String identityFingerprint,
    required String parentSignatureHex,
  }) {
    return _verify(
      claimedDomain: claimedDomain,
      identityFingerprint: identityFingerprint,
      parentSignatureHex: parentSignatureHex,
    ).timeout(
      _overallDeadline,
      onTimeout: () => TrustVerdict.unverified(
        domain: claimedDomain,
        reason:
            'The domain check did not finish in time. The network or the '
            'DNS resolvers may be unreachable.',
      ),
    );
  }

  Future<TrustVerdict> _verify({
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

    // The DNS pin and the server's assertion are independent fetches, so
    // they run together: serially, every check paid both round-trips end
    // to end while the responder waited on a spinner.
    final pinFuture = _shared(
      _pinInFlight,
      claimedDomain,
      () => _lookupTxtFingerprint(claimedDomain),
    );
    final infoFuture = _shared(
      _infoInFlight,
      claimedDomain,
      () => _fetchServerInfo(claimedDomain),
    );
    // Claim both errors now; an unawaited failure on the other branch
    // would otherwise surface as an unhandled async error.
    unawaited(infoFuture.catchError((Object _) => _ServerInfo.empty));

    final String? dnsFingerprint;
    try {
      dnsFingerprint = await pinFuture;
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
      info = await infoFuture;
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
  Future<String?> _lookupTxtFingerprint(String domain) {
    // The resolvers race, but only a *found* record wins outright. "No record
    // here" is not authoritative while another resolver may still have it -
    // propagation between public resolvers is uneven, and treating the first
    // empty answer as the truth reported published records as missing.
    final completer = Completer<String?>();
    var pending = _dohEndpoints.length;
    var anyAnsweredEmpty = false;
    _VerificationError? lastFailure;

    void settleIfDone() {
      if (pending > 0 || completer.isCompleted) return;
      if (anyAnsweredEmpty) {
        // Every resolver reachable agreed there is no record.
        completer.complete(null);
      } else {
        completer.completeError(
          lastFailure ?? _VerificationError('DNS lookup failed.'),
        );
      }
    }

    for (final endpoint in _dohEndpoints) {
      _lookupVia(endpoint, domain).then(
        (value) {
          pending--;
          if (value != null) {
            if (!completer.isCompleted) completer.complete(value);
            return;
          }
          anyAnsweredEmpty = true;
          settleIfDone();
        },
        onError: (Object e) {
          pending--;
          lastFailure = e is _VerificationError
              ? e
              : _VerificationError('DNS lookup failed: $e');
          settleIfDone();
        },
      );
    }
    return completer.future;
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

  /// Placeholder for the parallel branch whose error the awaiting side
  /// re-raises; never reaches a verdict.
  static const empty = _ServerInfo(publicKeyPem: '', claimedFingerprint: '');
}

class _VerificationError implements Exception {
  final String message;
  _VerificationError(this.message);
}

/// A stored verdict and when it was reached.
class _CachedVerdict {
  final TrustVerdict verdict;
  final DateTime checkedAt;

  const _CachedVerdict(this.verdict, this.checkedAt);

  Map<String, dynamic> toJson() => {
    'state': verdict.state.name,
    'domain': verdict.domain,
    'reason': verdict.reason,
    'rootFingerprint': verdict.rootFingerprint,
    'identityFingerprint': verdict.identityFingerprint,
    'checkedAt': checkedAt.toIso8601String(),
  };

  /// Null for anything unreadable or for a state that is never cached, so a
  /// tampered or outdated file degrades to "no cache" rather than to a wrong
  /// verdict.
  static _CachedVerdict? fromJson(Map<String, dynamic> json) {
    final checkedAt = DateTime.tryParse(json['checkedAt'] as String? ?? '');
    final domain = json['domain'] as String? ?? '';
    final reason = json['reason'] as String? ?? '';
    if (checkedAt == null || domain.isEmpty) return null;

    return switch (json['state'] as String? ?? '') {
      'verified' when (json['rootFingerprint'] as String? ?? '').isNotEmpty =>
        _CachedVerdict(
          TrustVerdict.verified(
            domain: domain,
            rootFingerprint: json['rootFingerprint'] as String,
            identityFingerprint: json['identityFingerprint'] as String? ?? '',
          ),
          checkedAt,
        ),
      'spoofed' => _CachedVerdict(
        TrustVerdict.spoofed(domain: domain, reason: reason),
        checkedAt,
      ),
      _ => null,
    };
  }
}
