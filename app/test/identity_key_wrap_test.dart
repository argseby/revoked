import 'package:flutter_test/flutter_test.dart';
import 'package:revoked_app/core/crypto/sealed_formats.dart';
import 'package:revoked_app/core/crypto/sealing.dart';

/// The wrap that carries an identity's private key between a person's
/// devices: only the workspace key opens it, and only for the identity,
/// workspace and epoch it was made for, so a server cannot re-serve it under
/// another name.
void main() {
  final workspaceKey = Sealing.newSymmetricKey();
  const pem =
      '-----BEGIN EC PRIVATE KEY-----\nMHcCAQEEIBc8c0u2wZDbrDBDGBMYJukMLGCQQ8BR5PeU\n-----END EC PRIVATE KEY-----\n';

  String wrap() => SealedFormats.wrapIdentityKey(
    workspaceKey: workspaceKey,
    privateKeyPem: pem,
    workspace: 'ws1',
    identity: 'id1',
    epoch: 2,
  );

  test('a device holding the workspace key opens the wrap', () {
    expect(
      SealedFormats.openIdentityKey(
        workspaceKey: workspaceKey,
        wrapped: wrap(),
        workspace: 'ws1',
        identity: 'id1',
        epoch: 2,
      ),
      pem,
    );
  });

  test('the wrap opens only under its own binding', () {
    final sealed = wrap();
    openAs(String workspace, String identity, int epoch) =>
        SealedFormats.openIdentityKey(
          workspaceKey: workspaceKey,
          wrapped: sealed,
          workspace: workspace,
          identity: identity,
          epoch: epoch,
        );
    expect(() => openAs('ws1', 'id2', 2), throwsA(isA<SealingException>()));
    expect(() => openAs('ws2', 'id1', 2), throwsA(isA<SealingException>()));
    expect(() => openAs('ws1', 'id1', 3), throwsA(isA<SealingException>()));
  });

  test('another key does not open it', () {
    expect(
      () => SealedFormats.openIdentityKey(
        workspaceKey: Sealing.newSymmetricKey(),
        wrapped: wrap(),
        workspace: 'ws1',
        identity: 'id1',
        epoch: 2,
      ),
      throwsA(isA<SealingException>()),
    );
  });

  test('the ciphertext does not give away the exact key length', () {
    // Padded to buckets: two keys of different length in the same bucket
    // seal to ciphertexts of one length.
    final a = SealedFormats.decode(wrap());
    final b = SealedFormats.decode(
      SealedFormats.wrapIdentityKey(
        workspaceKey: workspaceKey,
        privateKeyPem: '$pem\n\n\n\n',
        workspace: 'ws1',
        identity: 'id1',
        epoch: 2,
      ),
    );
    expect(a.length, b.length);
  });
}
