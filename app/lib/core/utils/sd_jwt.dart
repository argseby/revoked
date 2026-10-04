import 'dart:convert';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:pointycastle/export.dart' as pc;

/// The holder's side of an SD-JWT credential (RFC 9901): taking one apart,
/// and presenting it.
///
/// A credential is `<issuer JWT>~<disclosure>~<disclosure>~`. Each disclosure
/// opens one claim the issuer signed only a digest of, so a holder passes on
/// exactly the claims a verifier asked for and withholds the rest. A
/// presentation ends with a Key Binding JWT, signed with the identity key the
/// credential names: it proves that whoever presents the credential is the
/// one it was issued to, for this verifier and this occasion.
///
/// Pure Dart, so the tool that writes the fixture the Go tests verify can run
/// it without Flutter. The server's side of the same format is
/// `cmd/revoked/server/sdjwt.go`.

String _b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

Uint8List _unb64(String s) => base64Url.decode(base64Url.normalize(s));

/// The digest SD-JWT uses throughout: SHA-256 over the ASCII bytes,
/// base64url without padding.
String sdDigest(String ascii) =>
    _b64(pc.SHA256Digest().process(Uint8List.fromList(ascii.codeUnits)));

/// One claim of a credential, as its holder can disclose it.
class SdJwtDisclosure {
  /// The disclosure as it travels: base64url of `[salt, name, value]`.
  final String raw;
  final String name;
  final Object? value;

  const SdJwtDisclosure({
    required this.raw,
    required this.name,
    required this.value,
  });
}

/// A credential taken apart. Nothing about it is verified here: the app holds
/// credentials its own server checked before keeping them, and a verifier
/// checks a presentation itself.
class SdJwtCredential {
  /// The issuer-signed JWT, unchanged.
  final String jwt;
  final Map<String, dynamic> header;
  final Map<String, dynamic> payload;
  final List<SdJwtDisclosure> disclosures;

  const SdJwtCredential({
    required this.jwt,
    required this.header,
    required this.payload,
    required this.disclosures,
  });

  /// Throws a [FormatException] for anything that is not an issued
  /// credential.
  factory SdJwtCredential.parse(String credential) {
    final parts = credential.trim().split('~');
    if (parts.length < 2) {
      throw const FormatException('not an SD-JWT');
    }
    final jwt = parts.first;
    final segments = jwt.split('.');
    if (segments.length != 3) {
      throw const FormatException('not a compact JWT');
    }
    final header = jsonDecode(utf8.decode(_unb64(segments[0])));
    final payload = jsonDecode(utf8.decode(_unb64(segments[1])));
    if (header is! Map<String, dynamic> || payload is! Map<String, dynamic>) {
      throw const FormatException('malformed JWT');
    }

    final disclosures = <SdJwtDisclosure>[];
    // The last part is the key binding of a presentation, or empty.
    for (final raw in parts.sublist(1, parts.length - 1)) {
      if (raw.isEmpty) throw const FormatException('empty disclosure');
      final fields = jsonDecode(utf8.decode(_unb64(raw)));
      if (fields is! List || fields.length != 3 || fields[1] is! String) {
        throw const FormatException('malformed disclosure');
      }
      disclosures.add(
        SdJwtDisclosure(raw: raw, name: fields[1] as String, value: fields[2]),
      );
    }
    return SdJwtCredential(
      jwt: jwt,
      header: header,
      payload: payload,
      disclosures: disclosures,
    );
  }

  static SdJwtCredential? tryParse(String credential) {
    try {
      return SdJwtCredential.parse(credential);
    } catch (_) {
      return null;
    }
  }

  /// The attester, as the issuer identifier the credential carries.
  String get issuer => payload['iss'] as String? ?? '';

  /// What kind of statement this is.
  String get type => payload['vct'] as String? ?? '';

  /// The issuer JWT with exactly the disclosures named in [disclose], in the
  /// credential's own order: what a key binding commits to.
  String signedPart(Iterable<String> disclose) {
    final wanted = disclose.toSet();
    final buffer = StringBuffer('$jwt~');
    for (final d in disclosures) {
      if (wanted.contains(d.name)) buffer.write('${d.raw}~');
    }
    return buffer.toString();
  }
}

Uint8List _fixed(BigInt value, int length) {
  final out = Uint8List(length);
  var v = value;
  for (var i = length - 1; i >= 0; i--) {
    out[i] = (v & BigInt.from(0xff)).toInt();
    v = v >> 8;
  }
  return out;
}

/// Signs a JWS signing input with a P-256 key, in the form JWS uses for
/// ES256: r and s side by side, 32 bytes each — not the ASN.1 form the
/// challenge handshake sends.
Uint8List signEs256(String privateKeyPem, String signingInput) {
  final key = CryptoUtils.ecPrivateKeyFromPem(privateKeyPem);
  final signature = CryptoUtils.ecSign(
    key,
    Uint8List.fromList(utf8.encode(signingInput)),
    algorithmName: 'SHA-256/ECDSA',
  );
  return Uint8List.fromList([
    ..._fixed(signature.r, 32),
    ..._fixed(signature.s, 32),
  ]);
}

/// Presents [credential] to one verifier: only the claims in [disclose]
/// travel, and a key binding signed with [privateKeyPem] — the identity key
/// the credential names — ties them to [audience] and [nonce].
///
/// [audience] is the verifier as it names itself, [nonce] the value it chose
/// for this occasion. A presentation is refused by any other verifier and for
/// any other nonce, so one that is intercepted cannot be used again.
String presentSdJwt({
  required String credential,
  required Iterable<String> disclose,
  required String audience,
  required String nonce,
  required String privateKeyPem,
  DateTime? now,
}) {
  final parsed = SdJwtCredential.parse(credential);
  final held = parsed.disclosures.map((d) => d.name).toSet();
  for (final name in disclose) {
    if (!held.contains(name)) {
      throw FormatException('the credential holds no claim "$name"');
    }
  }
  final signed = parsed.signedPart(disclose);
  final issuedAt = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
  final input =
      '${_b64(utf8.encode(jsonEncode({'alg': 'ES256', 'typ': 'kb+jwt'})))}.'
      '${_b64(utf8.encode(jsonEncode({'iat': issuedAt, 'aud': audience, 'nonce': nonce, 'sd_hash': sdDigest(signed)})))}';
  return '$signed$input.${_b64(signEs256(privateKeyPem, input))}';
}
