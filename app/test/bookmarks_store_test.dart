import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobx/mobx.dart';
import 'package:revoked_app/core/models/user.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A bookmark somebody else put in this tray names who put it there, which is
/// the one thing a refusal can be aimed at: a workspace name is whatever its
/// own members typed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final blocked = <Map<String, dynamic>>[];
  var blocksAccepted = true;

  Future<http.Response> server(http.Request request) async {
    http.Response json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );
    final path = request.url.path;
    if (path == '/api/collections/bookmarks/records') {
      return json({
        'items': [
          {
            'id': 'b1',
            'origin': '',
            'slug': 'abc123',
            'kind': 'share',
            'label': 'Lease details',
            'sender': 'u2',
          },
          {
            'id': 'b2',
            'origin': '',
            'slug': 'def456',
            'kind': 'share',
            'label': 'One I saved myself',
          },
        ],
      });
    }
    if (path == '/api/collections/bookmarkGroups/records') {
      return json({'items': <Map<String, dynamic>>[]});
    }
    if (path == '/api/collections/contactBlocks/records') {
      if (!blocksAccepted) {
        return json({
          'code': 'contact_block_target_missing',
          'message':
              'A block requires an account, an email address or a '
              'domain.',
        }, 400);
      }
      blocked.add(jsonDecode(request.body) as Map<String, dynamic>);
      return json({'id': 'cb1', ...blocked.last});
    }
    return json({}, 404);
  }

  setUp(() async {
    blocked.clear();
    blocksAccepted = true;
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await Stores.init(httpClient: MockClient(server));
    await Stores.auth.initialize();
    runInAction(
      () => Stores.auth.currentUser = User.fromJson({
        'id': 'u1',
        'email': 'ada@example.com',
        'activeWorkspace': 'w1',
      }),
    );
  });

  test(
    'a handed-over bookmark carries its sender, one saved here does not',
    () async {
      final store = Stores.bookmarks;
      await store.load();

      expect(store.bookmarks.first.sender, 'u2');
      expect(store.bookmarks.last.sender, isEmpty);
    },
  );

  test('refusing a sender names the account, not the address', () async {
    final store = Stores.bookmarks;
    await store.load();

    final ok = await store.blockSender(
      user: Stores.auth.userId,
      sender: store.bookmarks.first.sender,
    );

    expect(ok, isTrue);
    expect(blocked.single, {'user': 'u1', 'blockedUser': 'u2'});
    // The bookmarks they already left are a separate choice: one of them is
    // how the sender was named in the first place.
    expect(store.bookmarks.length, 2);
  });

  test('a refusal the server turns down is reported, not swallowed', () async {
    blocksAccepted = false;
    final store = Stores.bookmarks;
    await store.load();

    final ok = await store.blockSender(user: 'u1', sender: 'u2');

    expect(ok, isFalse);
    expect(store.error, isNotNull);
  });
}
