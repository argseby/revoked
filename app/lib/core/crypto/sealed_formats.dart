import 'dart:convert';
import 'dart:typed_data';

import 'package:revoked_app/core/crypto/sealing.dart';

/// The contexts that bind each ciphertext and signature to what it is for, and
/// the encodings that travel over the API. A server that moves a ciphertext to
/// another record, epoch or device gets a failed decryption, not a wrong value.
abstract final class SealedFormats {
  static String encode(List<int> bytes) => base64Url.encode(bytes);

  static Uint8List decode(String text) =>
      Uint8List.fromList(base64Url.decode(base64Url.normalize(text)));

  /// Binds the record's key too: a server swapping the keys of two rows would
  /// otherwise show a real secret under the wrong name, and hand the wrong one
  /// to whatever asks for it by key.
  static Uint8List _valueAad(
    String workspace,
    String record,
    String recordKey,
    int version,
  ) => Sealing.context('revoked-record-v1', [
    workspace,
    record,
    recordKey,
    version,
  ]);

  static Uint8List _dekAad(
    String workspace,
    String record,
    int version,
    int epoch,
  ) => Sealing.context('revoked-dek-v1', [workspace, record, version, epoch]);

  static Uint8List workspaceKeyInfo(String workspace, int epoch) =>
      Sealing.context('revoked-workspace-key-v1', [workspace, epoch]);

  static Uint8List _priorAad(String workspace, int epoch) =>
      Sealing.context('revoked-prior-epoch-v1', [workspace, epoch]);

  static String sealValue({
    required Uint8List valueKey,
    required String value,
    required String workspace,
    required String record,
    required String recordKey,
    required int version,
  }) => encode(
    Sealing.aeadSeal(
      valueKey,
      _valueAad(workspace, record, recordKey, version),
      Sealing.pad(Uint8List.fromList(utf8.encode(value))),
    ),
  );

  static String openValue({
    required Uint8List valueKey,
    required String sealed,
    required String workspace,
    required String record,
    required String recordKey,
    required int version,
  }) => utf8.decode(
    Sealing.unpad(
      Sealing.aeadOpen(
        valueKey,
        _valueAad(workspace, record, recordKey, version),
        decode(sealed),
      ),
    ),
  );

  static String wrapValueKey({
    required Uint8List workspaceKey,
    required Uint8List valueKey,
    required String workspace,
    required String record,
    required int version,
    required int epoch,
  }) => encode(
    Sealing.aeadSeal(
      workspaceKey,
      _dekAad(workspace, record, version, epoch),
      valueKey,
    ),
  );

  static Uint8List openValueKey({
    required Uint8List workspaceKey,
    required String wrapped,
    required String workspace,
    required String record,
    required int version,
    required int epoch,
  }) => Sealing.aeadOpen(
    workspaceKey,
    _dekAad(workspace, record, version, epoch),
    decode(wrapped),
  );

  static String wrapPriorEpoch({
    required Uint8List newKey,
    required Uint8List priorKey,
    required String workspace,
    required int epoch,
  }) => encode(Sealing.aeadSeal(newKey, _priorAad(workspace, epoch), priorKey));

  static Uint8List openPriorEpoch({
    required Uint8List newKey,
    required String wrapped,
    required String workspace,
    required int epoch,
  }) => Sealing.aeadOpen(newKey, _priorAad(workspace, epoch), decode(wrapped));

  /// A workspace key for one device. Starts with a format byte, as everything
  /// stored here does.
  static String wrapWorkspaceKey({
    required Uint8List recipientHpkeKey,
    required Uint8List key,
    required String workspace,
    required int epoch,
  }) => encode([
    1,
    ...Sealing.hpkeSeal(
      recipientHpkeKey,
      workspaceKeyInfo(workspace, epoch),
      key,
    ),
  ]);

  static Uint8List openWorkspaceKey({
    required SealingKeyPair recipient,
    required String wrap,
    required String workspace,
    required int epoch,
  }) {
    final raw = decode(wrap);
    if (raw.isEmpty || raw[0] != 1) {
      throw const SealingException(
        'This data is in a format this app can\'t read.',
      );
    }
    final key = Sealing.hpkeOpen(
      recipient,
      workspaceKeyInfo(workspace, epoch),
      Uint8List.sublistView(raw, 1),
    );
    if (key.length != Sealing.keyLength) {
      throw const SealingException('This key is not the right length.');
    }
    return key;
  }

  /// What a device signs when it hands a workspace key to another. Anyone can
  /// encrypt to a public key, so without this a server could give a device a
  /// key of its own choosing and read everything written under it.
  ///
  /// [chainSeq] is how far the device list had got. A removal later than that
  /// means the key may be known to a device no longer on the list, which a
  /// client can then see for itself, without the server having to say so.
  static Uint8List wrapSignaturePayload({
    required String workspace,
    required int epoch,
    required Uint8List recipientHpkeKey,
    required String wrap,
    required int chainSeq,
  }) => Sealing.context('revoked-wrap-signature-v1', [
    workspace,
    epoch,
    recipientHpkeKey,
    wrap,
    chainSeq,
  ]);

  /// What a device signs to store a sealed record in plaintext again. A session
  /// can be stolen, and a device's key can't be taken from the server, so this is
  /// what stops a stolen session replacing a secret with whatever it likes.
  static Uint8List unsealPayload(
    String user,
    String record,
    int expectedVersion,
    String value,
  ) => Sealing.context('revoked-unseal-v1', [
    user,
    record,
    expectedVersion,
    value,
  ]);

  /// What the recovery key signs when it joins a list: the list's first entry.
  /// A public key alone proves nothing, because anyone can copy it into a list
  /// of their own. Only someone holding the recovery secret can produce this.
  static Uint8List recoveryAnchorPayload(String user, Uint8List rootHash) =>
      Sealing.context('revoked-recovery-anchor-v1', [user, rootHash]);

  /// What a passkey's key signs when it joins a list: the root, so a fresh device
  /// holding the same passkey can trust the list it is shown, and the credential,
  /// so the entry can't be passed off as another passkey's.
  static Uint8List passkeyAnchorPayload(
    String user,
    Uint8List rootHash,
    String credentialId,
  ) => Sealing.context('revoked-passkey-anchor-v1', [
    user,
    rootHash,
    credentialId,
  ]);
}

/// The keys a passkey holds, derived from what its PRF extension returns. The
/// same passkey gives the same output on every device it is synced to, so these
/// are the same pair wherever the person signs in with it.
abstract final class PasskeyKeys {
  static SealingKeyPair hpkeKey(Uint8List secret) => Sealing.deriveKeyPair(
    Sealing.derive(secret, 'revoked-passkey-hpke-v1', Sealing.keyLength),
  );

  static SealingKeyPair signingKey(Uint8List secret) => Sealing.deriveKeyPair(
    Sealing.derive(secret, 'revoked-passkey-sign-v1', Sealing.keyLength),
  );
}

/// Turns the recovery secret into the code a person writes down, and back.
///
/// Crockford base32 with a checksum, so a mistyped character says so rather
/// than failing as "wrong key" after the person has already searched for it.
abstract final class RecoveryCode {
  static const _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  static const _checksumLength = 2;

  static String encode(Uint8List secret) {
    final bytes = Uint8List.fromList([...secret, ..._checksum(secret)]);
    final out = StringBuffer();
    var buffer = 0;
    var bits = 0;
    var written = 0;
    void emit(int index) {
      if (written > 0 && written % 5 == 0) out.write('-');
      out.write(_alphabet[index]);
      written++;
    }

    for (final b in bytes) {
      buffer = (buffer << 8) | b;
      bits += 8;
      while (bits >= 5) {
        bits -= 5;
        emit((buffer >> bits) & 31);
      }
      buffer &= (1 << bits) - 1;
    }
    if (bits > 0) emit((buffer << (5 - bits)) & 31);
    return out.toString();
  }

  /// Returns null for anything that is not a whole, correctly typed code.
  static Uint8List? decode(String text) {
    final cleaned = text
        .toUpperCase()
        .replaceAll(RegExp(r'[\s-]'), '')
        .replaceAll('O', '0')
        .replaceAll(RegExp('[IL]'), '1');
    final out = BytesBuilder();
    var buffer = 0;
    var bits = 0;
    for (final char in cleaned.split('')) {
      final index = _alphabet.indexOf(char);
      if (index < 0) return null;
      buffer = (buffer << 5) | index;
      bits += 5;
      if (bits >= 8) {
        bits -= 8;
        out.addByte((buffer >> bits) & 0xff);
        buffer &= (1 << bits) - 1;
      }
    }
    final bytes = out.toBytes();
    if (bytes.length != Sealing.keyLength + _checksumLength) return null;
    final secret = Uint8List.sublistView(bytes, 0, Sealing.keyLength);
    final expected = _checksum(secret);
    final actual = Uint8List.sublistView(bytes, Sealing.keyLength);
    for (var i = 0; i < _checksumLength; i++) {
      if (expected[i] != actual[i]) return null;
    }
    return Uint8List.fromList(secret);
  }

  static List<int> _checksum(Uint8List secret) =>
      Sealing.sha256(secret).sublist(0, _checksumLength);

  static SealingKeyPair hpkeKey(Uint8List secret) => Sealing.deriveKeyPair(
    Sealing.derive(secret, 'revoked-recovery-hpke-v1', Sealing.keyLength),
  );

  static SealingKeyPair signingKey(Uint8List secret) => Sealing.deriveKeyPair(
    Sealing.derive(secret, 'revoked-recovery-sign-v1', Sealing.keyLength),
  );
}

/// One link in a person's signed list of devices.
///
/// The server hands this list out, so it could otherwise add a device of its
/// own and collect keys. Each entry is signed by a device already in the list,
/// and no key is wrapped to a device the list does not vouch for.
class DeviceChainEntry {
  static const String actionAdd = 'add';
  static const String actionRemove = 'remove';
  static const String kindDevice = 'device';
  static const String kindRecovery = 'recovery';
  static const String kindPasskey = 'passkey';

  final String user;
  final int seq;
  final String action;
  final String kind;
  final String label;

  /// On a passkey entry: the credential it derives from. Outside the signed
  /// payload, but the anchor signature covers it.
  final String credentialId;
  final Uint8List hpkePublicKey;
  final Uint8List signingPublicKey;

  /// The entry a removal withdraws; zero on an addition.
  final int targetSeq;
  final Uint8List previousHash;

  /// Equal to [seq] only on the first entry, which signs itself.
  final int signerSeq;

  /// On a recovery entry: the recovery key's signature over the list's root.
  final Uint8List anchorSignature;
  final Uint8List signature;

  const DeviceChainEntry({
    required this.user,
    required this.seq,
    required this.action,
    required this.kind,
    required this.label,
    this.credentialId = '',
    required this.hpkePublicKey,
    required this.signingPublicKey,
    required this.targetSeq,
    required this.previousHash,
    required this.signerSeq,
    required this.anchorSignature,
    required this.signature,
  });

  static Uint8List payload({
    required String user,
    required int seq,
    required String action,
    required String kind,
    required String label,
    required Uint8List hpkePublicKey,
    required Uint8List signingPublicKey,
    required int targetSeq,
    required Uint8List previousHash,
    required int signerSeq,
    required Uint8List anchorSignature,
  }) => Sealing.context('revoked-device-chain-v1', [
    user,
    seq,
    action,
    kind,
    label,
    hpkePublicKey,
    signingPublicKey,
    targetSeq,
    previousHash,
    signerSeq,
    anchorSignature,
  ]);

  factory DeviceChainEntry.sign({
    required String user,
    required int seq,
    required String action,
    required String kind,
    required String label,
    String credentialId = '',
    required Uint8List hpkePublicKey,
    required Uint8List signingPublicKey,
    required int targetSeq,
    required Uint8List previousHash,
    required int signerSeq,
    required SealingKeyPair signer,
    Uint8List? anchorSignature,
  }) => DeviceChainEntry(
    user: user,
    seq: seq,
    action: action,
    kind: kind,
    label: label,
    credentialId: credentialId,
    hpkePublicKey: hpkePublicKey,
    signingPublicKey: signingPublicKey,
    targetSeq: targetSeq,
    previousHash: previousHash,
    signerSeq: signerSeq,
    anchorSignature: anchorSignature ?? Uint8List(0),
    signature: Sealing.sign(
      signer,
      payload(
        user: user,
        seq: seq,
        action: action,
        kind: kind,
        label: label,
        hpkePublicKey: hpkePublicKey,
        signingPublicKey: signingPublicKey,
        targetSeq: targetSeq,
        previousHash: previousHash,
        signerSeq: signerSeq,
        anchorSignature: anchorSignature ?? Uint8List(0),
      ),
    ),
  );

  factory DeviceChainEntry.fromJson(
    Map<String, dynamic> json,
  ) => DeviceChainEntry(
    user: json['user'] as String,
    seq: (json['seq'] as num).toInt(),
    action: json['action'] as String,
    kind: json['kind'] as String? ?? '',
    label: json['label'] as String? ?? '',
    credentialId: json['credentialId'] as String? ?? '',
    hpkePublicKey: SealedFormats.decode(json['hpkePublicKey'] as String? ?? ''),
    signingPublicKey: SealedFormats.decode(
      json['signingPublicKey'] as String? ?? '',
    ),
    targetSeq: (json['targetSeq'] as num?)?.toInt() ?? 0,
    previousHash: SealedFormats.decode(json['previousHash'] as String? ?? ''),
    signerSeq: (json['signerSeq'] as num).toInt(),
    anchorSignature: SealedFormats.decode(
      json['anchorSignature'] as String? ?? '',
    ),
    signature: SealedFormats.decode(json['signature'] as String? ?? ''),
  );

  Map<String, dynamic> toJson() => {
    'seq': seq,
    'action': action,
    'kind': kind,
    'label': label,
    'credentialId': credentialId,
    'hpkePublicKey': SealedFormats.encode(hpkePublicKey),
    'signingPublicKey': SealedFormats.encode(signingPublicKey),
    'targetSeq': targetSeq,
    'previousHash': SealedFormats.encode(previousHash),
    'signerSeq': signerSeq,
    'anchorSignature': SealedFormats.encode(anchorSignature),
    'signature': SealedFormats.encode(signature),
  };

  Uint8List get _signedPayload => payload(
    user: user,
    seq: seq,
    action: action,
    kind: kind,
    label: label,
    hpkePublicKey: hpkePublicKey,
    signingPublicKey: signingPublicKey,
    targetSeq: targetSeq,
    previousHash: previousHash,
    signerSeq: signerSeq,
    anchorSignature: anchorSignature,
  );

  Uint8List get hash =>
      Sealing.sha256(Uint8List.fromList([..._signedPayload, ...signature]));

  bool verifiedBy(Uint8List signerKey) =>
      Sealing.verify(signerKey, _signedPayload, signature);
}

/// The outcome of walking a device list from its first entry.
class VerifiedChain {
  /// The entries that check out, in order. Anything after the first entry that
  /// fails is not trusted, however it reads.
  final List<DeviceChainEntry> entries;

  /// Whether the list as served contained something that did not check out.
  final bool broken;

  const VerifiedChain(this.entries, {required this.broken});

  static const empty = VerifiedChain([], broken: false);

  DeviceChainEntry? bySeq(int seq) {
    for (final e in entries) {
      if (e.seq == seq) return e;
    }
    return null;
  }

  Set<int> get _removed => {
    for (final e in entries)
      if (e.action == DeviceChainEntry.actionRemove) e.targetSeq,
  };

  bool isLive(int seq) {
    final entry = bySeq(seq);
    return entry != null &&
        entry.action == DeviceChainEntry.actionAdd &&
        !_removed.contains(seq);
  }

  List<DeviceChainEntry> get live => [
    for (final e in entries)
      if (isLive(e.seq)) e,
  ];

  Uint8List get headHash => entries.isEmpty ? Uint8List(0) : entries.last.hash;

  int get nextSeq => entries.isEmpty ? 1 : entries.last.seq + 1;

  int get headSeq => entries.isEmpty ? 0 : entries.last.seq;

  /// The newest removal. A key handed over before it may be known to whatever
  /// was removed.
  int get lastRemovalSeq {
    var last = 0;
    for (final e in entries) {
      if (e.action == DeviceChainEntry.actionRemove) last = e.seq;
    }
    return last;
  }

  DeviceChainEntry? get liveRecovery {
    for (final e in live) {
      if (e.kind == DeviceChainEntry.kindRecovery) return e;
    }
    return null;
  }

  List<DeviceChainEntry> get livePasskeys => [
    for (final e in live)
      if (e.kind == DeviceChainEntry.kindPasskey) e,
  ];

  DeviceChainEntry? livePasskey(String credentialId) {
    for (final e in livePasskeys) {
      if (e.credentialId == credentialId) return e;
    }
    return null;
  }

  /// Whether [credentialId] was ever on the list, live or removed. A passkey the
  /// person took off is not put back without them asking.
  bool everNamedPasskey(String credentialId) => entries.any(
    (e) =>
        e.kind == DeviceChainEntry.kindPasskey &&
        e.credentialId == credentialId,
  );

  /// What must also come off the list when [target] does: everything it added,
  /// and everything those added, including entries already removed. A stolen
  /// device could add a device, have that add a recovery key of its own, then
  /// remove the go-between, so only following live entries would miss what it
  /// planted. [keep] is the device doing the removing.
  List<int> removalsFor(int target, {required int keep}) {
    final closure = <int>{target};
    var grew = true;
    while (grew) {
      grew = false;
      for (final e in entries) {
        if (e.action != DeviceChainEntry.actionAdd) continue;
        if (e.seq == keep || closure.contains(e.seq)) continue;
        if (closure.contains(e.signerSeq)) {
          closure.add(e.seq);
          grew = true;
        }
      }
    }
    return [
      for (final seq in closure.toList()..sort())
        if (isLive(seq)) seq,
    ];
  }

  /// Verifies [served] for [user]: consecutive numbering, each entry pointing
  /// at the hash of the one before, and each signed by a device live at that
  /// point. A removed device cannot vouch for anything afterwards.
  static VerifiedChain verify(String user, List<DeviceChainEntry> served) {
    final sorted = [...served]..sort((a, b) => a.seq.compareTo(b.seq));
    final good = <DeviceChainEntry>[];
    for (final entry in sorted) {
      final sofar = VerifiedChain(good, broken: false);
      if (!_acceptable(entry, user, sofar)) {
        return VerifiedChain(good, broken: true);
      }
      good.add(entry);
    }
    return VerifiedChain(good, broken: false);
  }

  static bool _acceptable(
    DeviceChainEntry entry,
    String user,
    VerifiedChain sofar,
  ) {
    if (entry.user != user || entry.seq != sofar.nextSeq) return false;
    if (!_listEquals(entry.previousHash, sofar.headHash)) return false;

    if (sofar.entries.isEmpty) {
      return entry.action == DeviceChainEntry.actionAdd &&
          entry.kind == DeviceChainEntry.kindDevice &&
          Sealing.isValidPublicKey(entry.hpkePublicKey) &&
          Sealing.isValidPublicKey(entry.signingPublicKey) &&
          entry.signerSeq == entry.seq &&
          entry.verifiedBy(entry.signingPublicKey);
    }

    if (!sofar.isLive(entry.signerSeq)) return false;
    final signer = sofar.bySeq(entry.signerSeq)!;
    if (!entry.verifiedBy(signer.signingPublicKey)) return false;

    if (entry.action == DeviceChainEntry.actionRemove) {
      return sofar.isLive(entry.targetSeq);
    }
    if (entry.action != DeviceChainEntry.actionAdd) return false;
    if (!Sealing.isValidPublicKey(entry.hpkePublicKey) ||
        !Sealing.isValidPublicKey(entry.signingPublicKey)) {
      return false;
    }
    switch (entry.kind) {
      case DeviceChainEntry.kindDevice:
        return true;
      // One recovery key at a time, and it must have signed this list's root.
      // A second one is how a stolen device would keep a way in after its
      // removal.
      case DeviceChainEntry.kindRecovery:
        return sofar.liveRecovery == null &&
            Sealing.verify(
              entry.signingPublicKey,
              SealedFormats.recoveryAnchorPayload(
                user,
                sofar.entries.first.hash,
              ),
              entry.anchorSignature,
            );
      // Never the first entry, so never self-signed: a stolen session can make
      // a passkey, but nothing it holds may vouch for one.
      case DeviceChainEntry.kindPasskey:
        return entry.credentialId.isNotEmpty &&
            sofar.livePasskey(entry.credentialId) == null &&
            Sealing.verify(
              entry.signingPublicKey,
              SealedFormats.passkeyAnchorPayload(
                user,
                sofar.entries.first.hash,
                entry.credentialId,
              ),
              entry.anchorSignature,
            );
    }
    return false;
  }

  static bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// What a new device shows to one that is already trusted. It travels by QR
/// code or a copied string, not through the server, which is what stops the
/// server substituting a key of its own.
class DeviceInvite {
  static const _prefix = 'rvkdev1';

  final Uint8List hpkePublicKey;
  final Uint8List signingPublicKey;
  final String label;

  const DeviceInvite({
    required this.hpkePublicKey,
    required this.signingPublicKey,
    required this.label,
  });

  String encodeToString() => [
    _prefix,
    SealedFormats.encode(hpkePublicKey),
    SealedFormats.encode(signingPublicKey),
    SealedFormats.encode(utf8.encode(label)),
  ].join('.');

  /// Null for anything that is not a whole, well-formed invite.
  static DeviceInvite? tryParse(String text) {
    final parts = text.trim().split('.');
    if (parts.length != 4 || parts[0] != _prefix) return null;
    try {
      final hpke = SealedFormats.decode(parts[1]);
      final signing = SealedFormats.decode(parts[2]);
      if (hpke.length != Sealing.publicKeyLength ||
          signing.length != Sealing.publicKeyLength) {
        return null;
      }
      return DeviceInvite(
        hpkePublicKey: hpke,
        signingPublicKey: signing,
        label: utf8.decode(SealedFormats.decode(parts[3])),
      );
    } on FormatException {
      return null;
    }
  }
}

/// What a trusted device shows a device it just added, so the new one knows the
/// list it joined is the real one. A new device has nothing to check a list
/// against, and a server could otherwise build one around its public keys.
class DeviceConfirmation {
  static const _prefix = 'rvkjoin1';
  static const _hashLength = 16;

  final int seq;
  final Uint8List hashPrefix;

  const DeviceConfirmation(this.seq, this.hashPrefix);

  factory DeviceConfirmation.forEntry(DeviceChainEntry entry) =>
      DeviceConfirmation(
        entry.seq,
        Uint8List.sublistView(entry.hash, 0, _hashLength),
      );

  String encodeToString() =>
      [_prefix, '$seq', SealedFormats.encode(hashPrefix)].join('.');

  bool matches(DeviceChainEntry entry) {
    if (entry.seq != seq) return false;
    final hash = entry.hash;
    for (var i = 0; i < _hashLength; i++) {
      if (hash[i] != hashPrefix[i]) return false;
    }
    return true;
  }

  static DeviceConfirmation? tryParse(String text) {
    final parts = text.trim().split('.');
    if (parts.length != 3 || parts[0] != _prefix) return null;
    final seq = int.tryParse(parts[1]);
    if (seq == null || seq < 1) return null;
    try {
      final hash = SealedFormats.decode(parts[2]);
      if (hash.length != _hashLength) return null;
      return DeviceConfirmation(seq, hash);
    } on FormatException {
      return null;
    }
  }
}
