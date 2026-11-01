import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart' as pc;
import 'package:revoked_app/core/crypto/sealed_formats.dart';
import 'package:revoked_app/core/crypto/sealing.dart';

Uint8List _unhex(String s) => Uint8List.fromList([
  for (var i = 0; i < s.length; i += 2)
    int.parse(s.substring(i, i + 2), radix: 16),
]);

String _hex(List<int> b) =>
    b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  final vectors =
      jsonDecode(File('test/fixtures/sealing_vectors.json').readAsStringSync())
          as Map<String, dynamic>;
  final hpkeKey = SealingKeyPair(
    privateKey: _unhex(vectors['privateKey'] as String),
    publicKey: _unhex(vectors['publicKey'] as String),
  );

  group('agrees with Go crypto/hpke', () {
    test('derives the same key pair', () {
      final derived = Sealing.deriveKeyPair(_unhex(vectors['ikm'] as String));
      expect(_hex(derived.publicKey), vectors['publicKey']);
      expect(_hex(derived.privateKey), vectors['privateKey']);
    });

    test('opens what Go sealed', () {
      final opened = Sealing.hpkeOpen(
        hpkeKey,
        _unhex(vectors['info'] as String),
        _unhex(vectors['goSealed'] as String),
      );
      expect(_hex(opened), vectors['plaintext']);
    });

    test('verifies a Go signature', () {
      expect(
        Sealing.verify(
          _unhex(vectors['goSignPublicKey'] as String),
          _unhex(vectors['goSignMessage'] as String),
          _unhex(vectors['goSignature'] as String),
        ),
        isTrue,
      );
    });
  });

  group('stored formats keep opening', () {
    final workspace = vectors['workspace'] as String;
    final record = vectors['record'] as String;
    final version = vectors['version'] as int;
    final epoch = vectors['epoch'] as int;
    final valueKey = _unhex(vectors['valueKey'] as String);
    final workspaceKey = _unhex(vectors['workspaceKey'] as String);

    test('a sealed value', () {
      expect(
        SealedFormats.openValue(
          valueKey: valueKey,
          sealed: vectors['sealedValue'] as String,
          workspace: workspace,
          record: record,
          recordKey: vectors['recordKey'] as String,
          version: version,
        ),
        vectors['value'],
      );
    });

    test('a wrapped value key', () {
      expect(
        SealedFormats.openValueKey(
          workspaceKey: workspaceKey,
          wrapped: vectors['keyWrap'] as String,
          workspace: workspace,
          record: record,
          version: version,
          epoch: epoch,
        ),
        valueKey,
      );
    });

    test('a recovery code', () {
      final secret = RecoveryCode.decode(vectors['recoveryCode'] as String)!;
      expect(_hex(secret), vectors['recoverySecret']);
      expect(
        _hex(RecoveryCode.hpkeKey(secret).publicKey),
        vectors['recoveryHpkePublicKey'],
      );
      expect(
        _hex(RecoveryCode.signingKey(secret).publicKey),
        vectors['recoverySigningPublicKey'],
      );
    });
  });

  group('tampering fails', () {
    final key = Sealing.newSymmetricKey();
    String seal() => SealedFormats.sealValue(
      valueKey: key,
      value: 'secret',
      workspace: 'w1',
      record: 'r1',
      recordKey: 'k1',
      version: 1,
    );

    String open(
      String sealed, {
      String workspace = 'w1',
      String record = 'r1',
      String recordKey = 'k1',
      int version = 1,
    }) => SealedFormats.openValue(
      valueKey: key,
      sealed: sealed,
      workspace: workspace,
      record: record,
      recordKey: recordKey,
      version: version,
    );

    test('the untouched value opens', () => expect(open(seal()), 'secret'));

    test('moved to another record', () {
      expect(
        () => open(seal(), record: 'r2'),
        throwsA(isA<SealingException>()),
      );
    });

    test('moved to another workspace', () {
      expect(
        () => open(seal(), workspace: 'w2'),
        throwsA(isA<SealingException>()),
      );
    });

    test('moved to another record key', () {
      expect(
        () => open(seal(), recordKey: 'k2'),
        throwsA(isA<SealingException>()),
      );
    });

    test('replayed as another version', () {
      expect(() => open(seal(), version: 2), throwsA(isA<SealingException>()));
    });

    test('a flipped bit', () {
      final raw = SealedFormats.decode(seal());
      raw[raw.length - 1] ^= 1;
      expect(
        () => open(SealedFormats.encode(raw)),
        throwsA(isA<SealingException>()),
      );
    });

    test('a wrong key', () {
      final other = Sealing.newSymmetricKey();
      expect(
        () => SealedFormats.openValue(
          valueKey: other,
          sealed: seal(),
          workspace: 'w1',
          record: 'r1',
          recordKey: 'k1',
          version: 1,
        ),
        throwsA(isA<SealingException>()),
      );
    });

    test('HPKE opened with the wrong context', () {
      final pair = Sealing.generateKeyPair();
      final sealed = Sealing.hpkeSeal(
        pair.publicKey,
        SealedFormats.workspaceKeyInfo('w1', 1),
        _bytes('key'),
      );
      expect(
        () => Sealing.hpkeOpen(
          pair,
          SealedFormats.workspaceKeyInfo('w1', 2),
          sealed,
        ),
        throwsA(isA<SealingException>()),
      );
    });

    test('an off-curve public key is refused', () {
      final pair = Sealing.generateKeyPair();
      final bad = Uint8List.fromList(pair.publicKey);
      bad[bad.length - 1] ^= 1;
      expect(
        () => Sealing.hpkeSeal(bad, _bytes('i'), _bytes('p')),
        throwsA(isA<SealingException>()),
      );
    });
  });

  group('malformed data fails cleanly', () {
    test('short envelopes never throw anything but SealingException', () {
      final key = Sealing.newSymmetricKey();
      for (var n = 0; n < 40; n++) {
        final data = Uint8List(n);
        if (n > 0) data[0] = 1;
        expect(
          () => Sealing.aeadOpen(key, _bytes('a'), data),
          throwsA(isA<SealingException>()),
        );
      }
    });

    test('a wrapped key of the wrong length is refused', () {
      final pair = Sealing.generateKeyPair();
      final wrap = SealedFormats.encode([
        1,
        ...Sealing.hpkeSeal(
          pair.publicKey,
          SealedFormats.workspaceKeyInfo('w', 1),
          _bytes('short'),
        ),
      ]);
      expect(
        () => SealedFormats.openWorkspaceKey(
          recipient: pair,
          wrap: wrap,
          workspace: 'w',
          epoch: 1,
        ),
        throwsA(isA<SealingException>()),
      );
    });
  });

  group('context encoding', () {
    test('is unambiguous across part boundaries', () {
      expect(
        Sealing.context('l', ['ab', 'c']),
        isNot(Sealing.context('l', ['a', 'bc'])),
      );
    });
  });

  group('padding', () {
    test('hides short lengths in one bucket', () {
      expect(Sealing.pad(_bytes('1')).length, 64);
      expect(Sealing.pad(_bytes('a' * 63)).length, 64);
      expect(Sealing.pad(_bytes('a' * 64)).length, 256);
    });

    test('round-trips, including trailing zeros', () {
      final data = Uint8List.fromList([1, 2, 0, 0]);
      expect(Sealing.unpad(Sealing.pad(data)), data);
    });

    test('holds the longest value the server allows', () {
      expect(Sealing.pad(_bytes('😀' * 1000)).length, 4096);
    });

    test('refuses anything longer', () {
      expect(
        () => Sealing.pad(Uint8List(8192)),
        throwsA(isA<SealingException>()),
      );
    });
  });

  group('signatures', () {
    final pair = Sealing.generateKeyPair();

    test('verify', () {
      final sig = Sealing.sign(pair, _bytes('m'));
      expect(sig.length, Sealing.signatureLength);
      expect(Sealing.verify(pair.publicKey, _bytes('m'), sig), isTrue);
    });

    test('come out low-s, and refuse the malleated form', () {
      final n = pc.ECDomainParameters('secp256r1').n;
      for (var i = 0; i < 20; i++) {
        final message = _bytes('m$i');
        final sig = Sealing.sign(pair, message);
        final s = BigInt.parse(_hex(sig.sublist(32)), radix: 16);
        expect(s <= n >> 1, isTrue);
        final flipped = (n - s).toRadixString(16).padLeft(64, '0');
        final malleated = Uint8List.fromList([
          ...sig.sublist(0, 32),
          ..._unhex(flipped),
        ]);
        expect(Sealing.verify(pair.publicKey, message, malleated), isFalse);
      }
    });

    test('refuse another message or key', () {
      final sig = Sealing.sign(pair, _bytes('m'));
      expect(Sealing.verify(pair.publicKey, _bytes('n'), sig), isFalse);
      expect(
        Sealing.verify(Sealing.generateKeyPair().publicKey, _bytes('m'), sig),
        isFalse,
      );
    });
  });

  group('recovery code', () {
    test('tolerates spacing, case and look-alike characters', () {
      final secret = Sealing.randomBytes(32);
      final code = RecoveryCode.encode(secret);
      final sloppy = code
          .toLowerCase()
          .replaceAll('-', ' ')
          .replaceAll('0', 'o')
          .replaceAll('1', 'l');
      expect(RecoveryCode.decode(sloppy), secret);
    });

    test('catches a typo', () {
      final code = RecoveryCode.encode(Sealing.randomBytes(32));
      final i = code.indexOf(RegExp(r'[0-9A-Z]'));
      final swapped = code[i] == 'A' ? 'B' : 'A';
      final typo = code.replaceRange(i, i + 1, swapped);
      expect(RecoveryCode.decode(typo), isNull);
    });

    test('refuses a partial code', () {
      final code = RecoveryCode.encode(Sealing.randomBytes(32));
      expect(RecoveryCode.decode(code.substring(0, 20)), isNull);
    });
  });

  group('device chain', () {
    const user = 'u1';
    final first = Sealing.generateKeyPair();
    final firstHpke = Sealing.generateKeyPair();

    DeviceChainEntry add({
      required int seq,
      required SealingKeyPair signingKey,
      required SealingKeyPair signer,
      required int signerSeq,
      required Uint8List previousHash,
      String kind = DeviceChainEntry.kindDevice,
      String forUser = user,
    }) => DeviceChainEntry.sign(
      user: forUser,
      seq: seq,
      action: DeviceChainEntry.actionAdd,
      kind: kind,
      label: 'device $seq',
      hpkePublicKey: Sealing.generateKeyPair().publicKey,
      signingPublicKey: signingKey.publicKey,
      targetSeq: 0,
      previousHash: previousHash,
      signerSeq: signerSeq,
      signer: signer,
    );

    DeviceChainEntry root() => DeviceChainEntry.sign(
      user: user,
      seq: 1,
      action: DeviceChainEntry.actionAdd,
      kind: DeviceChainEntry.kindDevice,
      label: 'first',
      hpkePublicKey: firstHpke.publicKey,
      signingPublicKey: first.publicKey,
      targetSeq: 0,
      previousHash: Uint8List(0),
      signerSeq: 1,
      signer: first,
    );

    test('accepts a device signed by one already trusted', () {
      final a = root();
      final second = Sealing.generateKeyPair();
      final b = add(
        seq: 2,
        signingKey: second,
        signer: first,
        signerSeq: 1,
        previousHash: a.hash,
      );
      final chain = VerifiedChain.verify(user, [b, a]);
      expect(chain.broken, isFalse);
      expect(chain.live.map((e) => e.seq), [1, 2]);
    });

    test('refuses a device the server added on its own', () {
      final a = root();
      final server = Sealing.generateKeyPair();
      final forged = add(
        seq: 2,
        signingKey: server,
        signer: server,
        signerSeq: 1,
        previousHash: a.hash,
      );
      final chain = VerifiedChain.verify(user, [a, forged]);
      expect(chain.broken, isTrue);
      expect(chain.live.map((e) => e.seq), [1]);
    });

    test('refuses an entry that skips the one before it', () {
      final a = root();
      final b = add(
        seq: 3,
        signingKey: Sealing.generateKeyPair(),
        signer: first,
        signerSeq: 1,
        previousHash: a.hash,
      );
      expect(VerifiedChain.verify(user, [a, b]).broken, isTrue);
    });

    test('refuses an entry that does not point at the previous hash', () {
      final a = root();
      final b = add(
        seq: 2,
        signingKey: Sealing.generateKeyPair(),
        signer: first,
        signerSeq: 1,
        previousHash: Uint8List(32),
      );
      expect(VerifiedChain.verify(user, [a, b]).broken, isTrue);
    });

    test('refuses a list that belongs to someone else', () {
      expect(VerifiedChain.verify('u2', [root()]).broken, isTrue);
    });

    test('a removed device cannot vouch for anything afterwards', () {
      final a = root();
      final second = Sealing.generateKeyPair();
      final b = add(
        seq: 2,
        signingKey: second,
        signer: first,
        signerSeq: 1,
        previousHash: a.hash,
      );
      final removal = DeviceChainEntry.sign(
        user: user,
        seq: 3,
        action: DeviceChainEntry.actionRemove,
        kind: '',
        label: '',
        hpkePublicKey: Uint8List(0),
        signingPublicKey: Uint8List(0),
        targetSeq: 2,
        previousHash: b.hash,
        signerSeq: 1,
        signer: first,
      );
      final afterRemoval = add(
        seq: 4,
        signingKey: Sealing.generateKeyPair(),
        signer: second,
        signerSeq: 2,
        previousHash: removal.hash,
      );

      final fine = VerifiedChain.verify(user, [a, b, removal]);
      expect(fine.broken, isFalse);
      expect(fine.isLive(2), isFalse);
      expect(fine.isLive(1), isTrue);

      final chain = VerifiedChain.verify(user, [a, b, removal, afterRemoval]);
      expect(chain.broken, isTrue);
      expect(chain.isLive(4), isFalse);
    });

    test('a first entry cannot be a recovery key or signed by another', () {
      final other = Sealing.generateKeyPair();
      final bad = DeviceChainEntry.sign(
        user: user,
        seq: 1,
        action: DeviceChainEntry.actionAdd,
        kind: DeviceChainEntry.kindDevice,
        label: 'x',
        hpkePublicKey: firstHpke.publicKey,
        signingPublicKey: first.publicKey,
        targetSeq: 0,
        previousHash: Uint8List(0),
        signerSeq: 1,
        signer: other,
      );
      expect(VerifiedChain.verify(user, [bad]).broken, isTrue);
    });

    test('allows one recovery key, signed over the root', () {
      final a = root();
      final secret = Sealing.randomBytes(32);
      final signing = RecoveryCode.signingKey(secret);
      DeviceChainEntry recovery(
        int seq,
        Uint8List previous,
        SealingKeyPair key,
        Uint8List anchorRoot,
      ) => DeviceChainEntry.sign(
        user: user,
        seq: seq,
        action: DeviceChainEntry.actionAdd,
        kind: DeviceChainEntry.kindRecovery,
        label: 'r',
        hpkePublicKey: Sealing.generateKeyPair().publicKey,
        signingPublicKey: key.publicKey,
        targetSeq: 0,
        previousHash: previous,
        signerSeq: 1,
        signer: first,
        anchorSignature: Sealing.sign(
          key,
          SealedFormats.recoveryAnchorPayload(user, anchorRoot),
        ),
      );

      final good = recovery(2, a.hash, signing, a.hash);
      expect(VerifiedChain.verify(user, [a, good]).broken, isFalse);

      final second = recovery(3, good.hash, Sealing.generateKeyPair(), a.hash);
      expect(VerifiedChain.verify(user, [a, good, second]).broken, isTrue);

      final wrongRoot = recovery(2, a.hash, signing, Uint8List(32));
      expect(VerifiedChain.verify(user, [a, wrongRoot]).broken, isTrue);
    });

    test('survives a JSON round trip', () {
      final a = root();
      final json = jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>;
      json['user'] = user;
      final back = DeviceChainEntry.fromJson(json);
      expect(VerifiedChain.verify(user, [back]).broken, isFalse);
      expect(back.hash, a.hash);
    });
  });

  group('device invite', () {
    test('round-trips', () {
      final invite = DeviceInvite(
        hpkePublicKey: Sealing.generateKeyPair().publicKey,
        signingPublicKey: Sealing.generateKeyPair().publicKey,
        label: 'Sören\'s phone',
      );
      final back = DeviceInvite.tryParse(invite.encodeToString())!;
      expect(back.hpkePublicKey, invite.hpkePublicKey);
      expect(back.signingPublicKey, invite.signingPublicKey);
      expect(back.label, invite.label);
    });

    test('refuses anything else', () {
      expect(DeviceInvite.tryParse('https://example.com'), isNull);
      expect(DeviceInvite.tryParse('rvkdev1.AAAA.BBBB.CCCC'), isNull);
    });
  });
}
