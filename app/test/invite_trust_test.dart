import 'package:flutter_test/flutter_test.dart';
import 'package:revoked_app/core/models/invite.dart';

void main() {
  Map<String, dynamic> probe({
    Map<String, dynamic>? inviter,
    Map<String, dynamic>? server,
  }) => {
    'label': 'Join us',
    'permissions': <dynamic>[],
    'workspace': {'name': 'BMW'},
    'invitedBy': 'alice@bmw.example',
    'server': ?server,
    'inviter': ?inviter,
  };

  group('invite preview', () {
    // Without these the recipient has nothing to run the DNS chain against.
    test('carries the server trust block', () {
      final preview = InvitePreview.fromJson(
        probe(server: {'domain': 'bmw.example', 'rootFingerprint': 'ab' * 32}),
      );
      expect(preview.serverDomain, 'bmw.example');
      expect(preview.serverRootFingerprint, 'ab' * 32);
    });

    // An older server sends neither block; the screen must degrade to "no
    // opinion" rather than throw on the parse.
    test('survives a probe from a server that publishes neither', () {
      final preview = InvitePreview.fromJson(probe());
      expect(preview.serverDomain, isEmpty);
      expect(preview.inviter, isNull);
      expect(preview.invitedBy, 'alice@bmw.example');
    });

    test('reads the inviter attestation, identity included', () {
      final preview = InvitePreview.fromJson(
        probe(
          server: {'domain': 'bmw.example', 'rootFingerprint': 'ab' * 32},
          inviter: {
            'email': 'alice@bmw.example',
            'emailDomain': 'bmw.example',
            'serverDomain': 'bmw.example',
            'emailMatchesServer': true,
            'canStillInvite': true,
            'identity': {
              'name': 'Alice',
              'fingerprint': 'cd' * 32,
              'parentSignature': 'beef',
              'domainAtIssue': 'bmw.example',
              'status': 'active',
              'statusAssertion': {'payload': 'eyJ4IjoxfQ', 'signature': 'ab'},
            },
          },
        ),
      );

      final inviter = preview.inviter!;
      expect(inviter.emailMatchesServer, isTrue);
      expect(inviter.canStillInvite, isTrue);
      expect(inviter.hasIdentity, isTrue);
      expect(inviter.identityRevoked, isFalse);
      expect(inviter.statusAssertion, isNotNull);
    });

    // The address is the thing a recipient is most likely to trust on sight,
    // so an address outside the server's own domain must not read as vouched.
    test('an address outside the server domain does not match', () {
      final preview = InvitePreview.fromJson(
        probe(
          inviter: {
            'email': 'alice@gmail.com',
            'emailDomain': 'gmail.com',
            'serverDomain': 'bmw.example',
            'emailMatchesServer': false,
            'canStillInvite': true,
          },
        ),
      );
      expect(preview.inviter!.emailMatchesServer, isFalse);
      expect(preview.inviter!.hasIdentity, isFalse);
    });

    test('surfaces a revoked inviter identity and lost authority', () {
      final preview = InvitePreview.fromJson(
        probe(
          inviter: {
            'email': 'alice@bmw.example',
            'emailDomain': 'bmw.example',
            'serverDomain': 'bmw.example',
            'emailMatchesServer': true,
            'canStillInvite': false,
            'identity': {'fingerprint': 'cd' * 32, 'status': 'revoked'},
          },
        ),
      );
      expect(preview.inviter!.canStillInvite, isFalse);
      expect(preview.inviter!.identityRevoked, isTrue);
    });

    // canStillInvite defaults to true so an older server, which cannot report
    // it, is not painted as compromised on every invite.
    test('missing authority flag defaults to permissive', () {
      final preview = InvitePreview.fromJson(
        probe(inviter: {'email': 'a@b.test'}),
      );
      expect(preview.inviter!.canStillInvite, isTrue);
      expect(preview.inviter!.identityRevoked, isFalse);
    });
  });
}
