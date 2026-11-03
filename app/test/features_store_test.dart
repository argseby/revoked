import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobx/mobx.dart';
import 'package:revoked_app/core/models/feature.dart';
import 'package:revoked_app/core/models/invite.dart';
import 'package:revoked_app/core/models/user.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A screen shows a feature only where the person chose it and the workspace
/// lets them use it. The first is the account's; the second is the member
/// record's, and neither alone is enough.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final saved = <List<dynamic>>[];
  var catalogueServed = true;

  Future<http.Response> server(http.Request request) async {
    http.Response json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );
    if (request.url.path == '/api/features') {
      if (!catalogueServed) return json({}, 500);
      return json({
        'features': [
          {
            'key': 'sharing',
            'label': 'Sharing',
            'description': 'Share links.',
            'permission': 'shares:read',
            'defaultOn': true,
          },
          {
            'key': 'requests',
            'label': 'Requests',
            'description': 'Ask people.',
            'permission': 'requests:read',
            'defaultOn': true,
          },
          {
            'key': 'developer',
            'label': 'Developer',
            'description': 'API keys.',
            'permission': '',
            'defaultOn': false,
          },
        ],
        'presets': [
          {
            'key': 'vault',
            'label': 'Vault only',
            'description': 'Records.',
            'permissions': ['vault:read'],
            'features': [],
          },
        ],
      });
    }
    if (request.url.path == '/api/account/features' &&
        request.method == 'PUT') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      saved.add(body['features'] as List<dynamic>);
      if ((body['features'] as List).contains('teleport')) {
        return json({'code': 'unknown_feature', 'message': 'Unknown.'}, 400);
      }
      return json({'features': body['features']});
    }
    return json({}, 404);
  }

  User user({List<String>? features}) => User.fromJson({
    'id': 'u1',
    'email': 'ada@example.com',
    'activeWorkspace': 'w1',
    'features': ?features,
  });

  WorkspaceMemberDetail self(List<String> permissions) =>
      WorkspaceMemberDetail.fromJson({
        'id': 'm1',
        'user': 'u1',
        'email': 'ada@example.com',
        'role': 'member',
        'isSelf': true,
        'permissions': [
          for (final p in permissions) {'key': p, 'label': p},
        ],
      });

  setUp(() async {
    saved.clear();
    catalogueServed = true;
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await Stores.init(httpClient: MockClient(server));
    // Stores.init restores the stored session in the background and would
    // null the account set below once it finds none.
    await Stores.auth.initialize();
    runInAction(() => Stores.auth.currentUser = user());
  });

  test('a fresh account sees the defaults, with Developer off', () async {
    final store = Stores.features;
    expect(store.hasChosen, isFalse);
    expect(store.visible(Feature.sharing), isTrue);
    expect(store.visible(Feature.developer), isFalse);

    await store.load();
    expect(store.catalogue.map((f) => f.key), [
      'sharing',
      'requests',
      'developer',
    ]);
    expect(store.presets.single.label, 'Vault only');
    expect(store.visible(Feature.sharing), isTrue);
    expect(store.visible(Feature.developer), isFalse);
    expect(store.labelFor(Feature.developer), 'Developer');
  });

  test('what the account chose replaces the defaults', () {
    runInAction(() => Stores.auth.currentUser = user(features: ['developer']));
    final store = Stores.features;
    expect(store.hasChosen, isTrue);
    expect(store.visible(Feature.developer), isTrue);
    expect(store.visible(Feature.sharing), isFalse);
    expect(store.visible(Feature.requests), isFalse);
  });

  test(
    'chosen but not permitted is hidden; permitted but not chosen too',
    () async {
      final store = Stores.features;
      await store.load();
      runInAction(() {
        Stores.auth.currentUser = user(features: ['sharing']);
        Stores.invites.members.add(self(['requests:read']));
      });
      // Sharing is on, but this member may not see shares.
      expect(store.isOn(Feature.sharing), isTrue);
      expect(store.isPermitted(Feature.sharing), isFalse);
      expect(store.visible(Feature.sharing), isFalse);
      // Requests are allowed, but off.
      expect(store.isPermitted(Feature.requests), isTrue);
      expect(store.visible(Feature.requests), isFalse);
      // Nothing is needed for Developer beyond choosing it.
      expect(store.isPermitted(Feature.developer), isTrue);

      runInAction(() {
        Stores.invites.members.clear();
        Stores.invites.members.add(self(['shares:read']));
      });
      expect(store.visible(Feature.sharing), isTrue);
    },
  );

  test('until the roster is known, nothing is hidden on a guess', () async {
    final store = Stores.features;
    await store.load();
    runInAction(() => Stores.auth.currentUser = user(features: ['sharing']));
    expect(store.visible(Feature.sharing), isTrue);
  });

  test('turning one on keeps the rest and updates the account', () async {
    final store = Stores.features;
    await store.load();
    runInAction(() => Stores.auth.currentUser = user(features: ['sharing']));

    expect(await store.turnOn(Feature.developer), isTrue);
    expect(saved.single, unorderedEquals(['sharing', 'developer']));
    expect(Stores.auth.currentUser!.features, contains('developer'));
    expect(store.visible(Feature.developer), isTrue);

    expect(await store.turnOff(Feature.sharing), isTrue);
    expect(store.visible(Feature.sharing), isFalse);
    expect(store.visible(Feature.developer), isTrue);
  });

  test('a refused save leaves the account as it was', () async {
    final store = Stores.features;
    runInAction(() => Stores.auth.currentUser = user(features: ['sharing']));
    expect(await store.save(['sharing', 'teleport']), isFalse);
    expect(store.error, isNotNull);
    expect(Stores.auth.currentUser!.features, ['sharing']);
  });

  test(
    'a catalogue that will not load leaves the keys\' own defaults',
    () async {
      catalogueServed = false;
      final store = Stores.features;
      await store.load();
      expect(store.loadState.error, isNotNull);
      expect(store.ordered, Feature.values);
      expect(store.visible(Feature.contacts), isTrue);
      expect(store.visible(Feature.developer), isFalse);
    },
  );
}
