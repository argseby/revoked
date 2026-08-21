import 'package:flutter_test/flutter_test.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/utils/deep_links.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Stores.init();
  });

  group('invite key parsing', () {
    test('a bare key is taken as-is', () {
      expect(DeepLinks.inviteTokenFrom('abc123'), 'abc123');
      expect(DeepLinks.inviteTokenFrom('  abc123  '), 'abc123');
    });

    test('a plain invite link yields just the key', () {
      expect(DeepLinks.inviteTokenFrom('revoked://i/abc123'), 'abc123');
    });

    // Links are origin-qualified, and the host is not part of the key — a
    // parser that kept it would send an unspendable token to the server.
    test('an origin-qualified link yields the key without the host', () {
      final token = DeepLinks.inviteTokenFrom(
        'revoked://i/bmw.example:3000/abc123',
      );
      expect(token, 'abc123');
      expect(token, isNot(contains('bmw.example')));
      expect(token, isNot(contains('?')));
    });

    test('empty input yields an empty key rather than throwing', () {
      expect(DeepLinks.inviteTokenFrom(''), '');
      expect(DeepLinks.inviteTokenFrom('   '), '');
    });

    test('something that is not a link falls through unchanged', () {
      expect(
        DeepLinks.inviteTokenFrom('https://example.com/x'),
        'https://example.com/x',
      );
    });
  });

  group('join draft', () {
    test('the store reads the pasted key through the shared parser', () {
      Stores.invites.resetJoinDraft();
      Stores.invites.joinKeyController.text = 'revoked://i/bmw.example/tok99';
      expect(Stores.invites.joinToken, 'tok99');
    });

    // The sheet is reopened often; a key left behind would be offered as the
    // next one to spend.
    test('resetting clears the key and everything shown about it', () {
      Stores.invites.joinKeyController.text = 'leftover';
      Stores.invites.resetJoinDraft();
      expect(Stores.invites.joinToken, '');
      expect(Stores.invites.acceptPreview, isNull);
      expect(Stores.invites.inviteTrustVerdict, isNull);
      expect(Stores.invites.acceptError, isNull);
    });
  });
}
