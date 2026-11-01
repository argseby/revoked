import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart' as pc;

/// The primitives and wire formats behind end-to-end encrypted records.
///
/// Stateless and free of I/O. Formats are described in E2EE.md and pinned by
/// `test/fixtures/sealing_vectors.json`, which Go's `crypto/hpke` checks from
/// the other side (`util/sealing_vectors_test.go`) — a format change here must
/// fail there.
abstract final class Sealing {
  static const int keyLength = 32;
  static const int publicKeyLength = 65;
  static const int signatureLength = 64;
  static const int _nonceLength = 12;
  static const int _tagLength = 16;
  static const int _formatVersion = 1;

  static const List<int> _paddingBuckets = [64, 256, 1024, 4096];

  static final pc.ECDomainParameters _curve = pc.ECDomainParameters(
    'secp256r1',
  );

  // DHKEM(P-256, HKDF-SHA256), HKDF-SHA256, AES-256-GCM.
  static final Uint8List _kemSuite = _concat([
    ascii.encode('KEM'),
    _i2osp(16, 2),
  ]);
  static final Uint8List _hpkeSuite = _concat([
    ascii.encode('HPKE'),
    _i2osp(16, 2),
    _i2osp(1, 2),
    _i2osp(2, 2),
  ]);

  static final BigInt _halfOrder = _curve.n >> 1;

  static final Random _random = Random.secure();

  static Uint8List randomBytes(int length) {
    final out = Uint8List(length);
    for (var i = 0; i < length; i++) {
      out[i] = _random.nextInt(256);
    }
    return out;
  }

  static Uint8List newSymmetricKey() => randomBytes(keyLength);

  static SealingKeyPair generateKeyPair() {
    while (true) {
      final candidate = _toBigInt(randomBytes(keyLength));
      if (candidate > BigInt.zero && candidate < _curve.n) {
        return _keyPairFromScalar(candidate);
      }
    }
  }

  /// RFC 9180 §7.1.3. Used for the recovery key, whose key pairs must be
  /// reproducible from the code the person wrote down.
  static SealingKeyPair deriveKeyPair(Uint8List ikm) {
    final prk = _labeledExtract(Uint8List(0), 'dkp_prk', ikm, _kemSuite);
    for (var counter = 0; counter < 256; counter++) {
      final candidate = _toBigInt(
        _labeledExpand(
          prk,
          'candidate',
          Uint8List.fromList([counter]),
          keyLength,
          _kemSuite,
        ),
      );
      if (candidate > BigInt.zero && candidate < _curve.n) {
        return _keyPairFromScalar(candidate);
      }
    }
    throw StateError('Could not derive a key pair.');
  }

  /// Single-shot HPKE base mode: `enc ‖ ciphertext`. [info] binds the message
  /// to its context, so a wrap cannot be replayed as a wrap for something else.
  static Uint8List hpkeSeal(
    Uint8List recipientPublicKey,
    Uint8List info,
    Uint8List plaintext,
  ) {
    final recipient = _decodePoint(recipientPublicKey);
    final ephemeral = generateKeyPair();
    final dh = _diffieHellman(_toBigInt(ephemeral.privateKey), recipient);
    final secret = _kemSharedSecret(
      dh,
      ephemeral.publicKey,
      recipientPublicKey,
    );
    final (key, nonce) = _keySchedule(secret, info);
    return _concat([
      ephemeral.publicKey,
      _aesGcm(true, key, nonce, Uint8List(0), plaintext),
    ]);
  }

  static Uint8List hpkeOpen(
    SealingKeyPair recipient,
    Uint8List info,
    Uint8List sealed,
  ) {
    if (sealed.length <= publicKeyLength) {
      throw const SealingException('This data is too short to open.');
    }
    final enc = Uint8List.sublistView(sealed, 0, publicKeyLength);
    final dh = _diffieHellman(
      _toBigInt(recipient.privateKey),
      _decodePoint(enc),
    );
    final secret = _kemSharedSecret(dh, enc, recipient.publicKey);
    final (key, nonce) = _keySchedule(secret, info);
    return _aesGcm(
      false,
      key,
      nonce,
      Uint8List(0),
      Uint8List.sublistView(sealed, publicKeyLength),
    );
  }

  /// `version ‖ nonce ‖ AES-256-GCM(key, plaintext, version ‖ aad)`. The version
  /// is authenticated, so a later format can't be downgraded to this one.
  static Uint8List aeadSeal(Uint8List key, Uint8List aad, Uint8List plaintext) {
    final nonce = randomBytes(_nonceLength);
    final version = Uint8List.fromList([_formatVersion]);
    return _concat([
      version,
      nonce,
      _aesGcm(true, key, nonce, _concat([version, aad]), plaintext),
    ]);
  }

  static Uint8List aeadOpen(Uint8List key, Uint8List aad, Uint8List sealed) {
    if (sealed.length < 1 + _nonceLength + _tagLength ||
        sealed[0] != _formatVersion) {
      throw const SealingException(
        'This data is in a format this app can\'t read.',
      );
    }
    final version = Uint8List.sublistView(sealed, 0, 1);
    return _aesGcm(
      false,
      key,
      Uint8List.sublistView(sealed, 1, 1 + _nonceLength),
      _concat([version, aad]),
      Uint8List.sublistView(sealed, 1 + _nonceLength),
    );
  }

  /// Unambiguous encoding of a context: a bare concatenation would let
  /// `("ab", "c")` and `("a", "bc")` authenticate as the same thing, so every
  /// string is length-prefixed and every int a fixed eight bytes.
  static Uint8List context(String label, List<Object> parts) {
    final out = BytesBuilder();
    void addBytes(List<int> bytes) {
      out.add(_i2osp(bytes.length, 4));
      out.add(bytes);
    }

    addBytes(utf8.encode(label));
    for (final part in parts) {
      switch (part) {
        case String s:
          addBytes(utf8.encode(s));
        case int i:
          out.add(_i2osp(i, 8));
        case List<int> b:
          addBytes(b);
        default:
          throw ArgumentError('Unsupported context part: ${part.runtimeType}');
      }
    }
    return out.toBytes();
  }

  /// Pads to the next bucket, so a ciphertext does not give away the length of
  /// a short PIN or password. ISO/IEC 7816-4: a 0x80 marker, then zeros.
  static Uint8List pad(Uint8List plaintext) {
    final needed = plaintext.length + 1;
    for (final bucket in _paddingBuckets) {
      if (needed <= bucket) {
        final out = Uint8List(bucket);
        out.setAll(0, plaintext);
        out[plaintext.length] = 0x80;
        return out;
      }
    }
    throw const SealingException('This value is too long to encrypt.');
  }

  static Uint8List unpad(Uint8List padded) {
    for (var i = padded.length - 1; i >= 0; i--) {
      if (padded[i] == 0x80) return Uint8List.sublistView(padded, 0, i);
      if (padded[i] != 0) break;
    }
    throw const SealingException('This data is not padded correctly.');
  }

  /// Deterministic low-s ECDSA (RFC 6979) over SHA-256, as raw `r ‖ s`: a nonce from
  /// the signing key cannot repeat under a bad random source, and a repeated
  /// nonce would hand out the private key.
  static Uint8List sign(SealingKeyPair signer, Uint8List message) {
    final s = pc.ECDSASigner(pc.SHA256Digest(), pc.HMac(pc.SHA256Digest(), 64));
    s.init(
      true,
      pc.PrivateKeyParameter<pc.ECPrivateKey>(
        pc.ECPrivateKey(_toBigInt(signer.privateKey), _curve),
      ),
    );
    final sig = s.generateSignature(message) as pc.ECSignature;
    final low = sig.s > _halfOrder ? _curve.n - sig.s : sig.s;
    return _concat([_fromBigInt(sig.r, 32), _fromBigInt(low, 32)]);
  }

  static bool verify(
    Uint8List publicKey,
    Uint8List message,
    Uint8List signature,
  ) {
    if (signature.length != signatureLength) return false;
    // (r, n-s) verifies as well as (r, s). Device-list entries are hashed with
    // their signature, so without one canonical form a server could change a
    // hash without holding any key.
    final s = _toBigInt(Uint8List.sublistView(signature, 32));
    if (s > _halfOrder) return false;
    try {
      final v = pc.ECDSASigner(pc.SHA256Digest());
      v.init(
        false,
        pc.PublicKeyParameter<pc.ECPublicKey>(
          pc.ECPublicKey(_decodePoint(publicKey), _curve),
        ),
      );
      return v.verifySignature(
        message,
        pc.ECSignature(_toBigInt(Uint8List.sublistView(signature, 0, 32)), s),
      );
    } on SealingException {
      return false;
    } on ArgumentError {
      return false;
    }
  }

  static Uint8List sha256(Uint8List data) => pc.SHA256Digest().process(data);

  /// HKDF-SHA256 with a purpose label, for keys derived from the recovery code.
  static Uint8List derive(Uint8List secret, String purpose, int length) =>
      _hkdfExpand(
        _hkdfExtract(Uint8List(0), secret),
        Uint8List.fromList(utf8.encode(purpose)),
        length,
      );

  /// Rejects anything that is not an on-curve uncompressed P-256 point: an
  /// off-curve key is how an invalid-curve attack extracts a private key.
  static pc.ECPoint _decodePoint(Uint8List encoded) {
    if (encoded.length != publicKeyLength || encoded[0] != 0x04) {
      throw const SealingException('This public key is not valid.');
    }
    final x = _toBigInt(Uint8List.sublistView(encoded, 1, 33));
    final y = _toBigInt(Uint8List.sublistView(encoded, 33));
    final p = (_curve.curve as dynamic).q as BigInt;
    if (x >= p || y >= p) {
      throw const SealingException('This public key is not valid.');
    }
    final a = _curve.curve.a!.toBigInteger()!;
    final b = _curve.curve.b!.toBigInteger()!;
    if ((y * y - (x * x * x + a * x + b)) % p != BigInt.zero) {
      throw const SealingException('This public key is not valid.');
    }
    return _curve.curve.createPoint(x, y);
  }

  static Uint8List _encodePoint(pc.ECPoint point) => _concat([
    Uint8List.fromList([0x04]),
    _fromBigInt(point.x!.toBigInteger()!, 32),
    _fromBigInt(point.y!.toBigInteger()!, 32),
  ]);

  static SealingKeyPair _keyPairFromScalar(BigInt scalar) => SealingKeyPair(
    privateKey: _fromBigInt(scalar, keyLength),
    publicKey: _encodePoint((_curve.G * scalar)!),
  );

  static Uint8List _diffieHellman(BigInt scalar, pc.ECPoint peer) {
    final shared = peer * scalar;
    if (shared == null || shared.isInfinity) {
      throw const SealingException('This public key is not valid.');
    }
    return _fromBigInt(shared.x!.toBigInteger()!, 32);
  }

  static Uint8List _kemSharedSecret(
    Uint8List dh,
    Uint8List enc,
    Uint8List recipientPublicKey,
  ) {
    final prk = _labeledExtract(Uint8List(0), 'eae_prk', dh, _kemSuite);
    return _labeledExpand(
      prk,
      'shared_secret',
      _concat([enc, recipientPublicKey]),
      keyLength,
      _kemSuite,
    );
  }

  static (Uint8List, Uint8List) _keySchedule(
    Uint8List sharedSecret,
    Uint8List info,
  ) {
    final empty = Uint8List(0);
    final pskIdHash = _labeledExtract(empty, 'psk_id_hash', empty, _hpkeSuite);
    final infoHash = _labeledExtract(empty, 'info_hash', info, _hpkeSuite);
    final context = _concat([
      Uint8List.fromList([0]),
      pskIdHash,
      infoHash,
    ]);
    final secret = _labeledExtract(sharedSecret, 'secret', empty, _hpkeSuite);
    return (
      _labeledExpand(secret, 'key', context, keyLength, _hpkeSuite),
      _labeledExpand(secret, 'base_nonce', context, _nonceLength, _hpkeSuite),
    );
  }

  static Uint8List _labeledExtract(
    Uint8List salt,
    String label,
    Uint8List ikm,
    Uint8List suite,
  ) => _hkdfExtract(
    salt,
    _concat([ascii.encode('HPKE-v1'), suite, ascii.encode(label), ikm]),
  );

  static Uint8List _labeledExpand(
    Uint8List prk,
    String label,
    Uint8List info,
    int length,
    Uint8List suite,
  ) => _hkdfExpand(
    prk,
    _concat([
      _i2osp(length, 2),
      ascii.encode('HPKE-v1'),
      suite,
      ascii.encode(label),
      info,
    ]),
    length,
  );

  static Uint8List _hmac(Uint8List key, Uint8List data) {
    final mac = pc.HMac(pc.SHA256Digest(), 64)..init(pc.KeyParameter(key));
    return mac.process(data);
  }

  static Uint8List _hkdfExtract(Uint8List salt, Uint8List ikm) =>
      _hmac(salt.isEmpty ? Uint8List(32) : salt, ikm);

  static Uint8List _hkdfExpand(Uint8List prk, Uint8List info, int length) {
    final out = BytesBuilder();
    var block = Uint8List(0);
    for (var i = 1; out.length < length; i++) {
      block = _hmac(
        prk,
        _concat([
          block,
          info,
          Uint8List.fromList([i]),
        ]),
      );
      out.add(block);
    }
    return Uint8List.sublistView(out.toBytes(), 0, length);
  }

  static Uint8List _aesGcm(
    bool encrypt,
    Uint8List key,
    Uint8List nonce,
    Uint8List aad,
    Uint8List input,
  ) {
    final cipher = pc.GCMBlockCipher(pc.AESEngine())
      ..init(encrypt, pc.AEADParameters(pc.KeyParameter(key), 128, nonce, aad));
    try {
      return cipher.process(input);
    } on pc.InvalidCipherTextException {
      throw const SealingException('This data could not be decrypted.');
    }
  }

  static Uint8List _concat(List<List<int>> parts) {
    final out = BytesBuilder(copy: false);
    for (final p in parts) {
      out.add(p);
    }
    return out.toBytes();
  }

  static Uint8List _i2osp(int value, int length) {
    final out = Uint8List(length);
    var v = value;
    for (var i = length - 1; i >= 0; i--) {
      out[i] = v & 0xff;
      v >>= 8;
    }
    return out;
  }

  static BigInt _toBigInt(List<int> bytes) {
    var out = BigInt.zero;
    for (final b in bytes) {
      out = (out << 8) | BigInt.from(b);
    }
    return out;
  }

  static Uint8List _fromBigInt(BigInt value, int length) {
    final out = Uint8List(length);
    var v = value;
    final mask = BigInt.from(0xff);
    for (var i = length - 1; i >= 0; i--) {
      out[i] = (v & mask).toInt();
      v >>= 8;
    }
    return out;
  }
}

/// A P-256 key pair: a 32-byte scalar and an uncompressed public point.
class SealingKeyPair {
  final Uint8List privateKey;
  final Uint8List publicKey;

  const SealingKeyPair({required this.privateKey, required this.publicKey});
}

/// Data that failed to decode or authenticate. The message is safe to show:
/// it never names key material.
class SealingException implements Exception {
  final String message;

  const SealingException(this.message);

  @override
  String toString() => message;
}
