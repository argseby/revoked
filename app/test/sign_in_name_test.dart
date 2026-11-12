import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobx/mobx.dart';
import 'package:revoked_app/core/models/sign_in_request.dart';
import 'package:revoked_app/core/models/sign_in_service.dart';
import 'package:revoked_app/core/models/user.dart';
import 'package:revoked_app/core/services/crypto_service.dart';
import 'package:revoked_app/core/services/device_unlock.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/theme/app_theme.dart';
import 'package:revoked_app/features/connections/view/sign_in_approval_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _AlwaysUnlocked implements DeviceUnlock {
  @override
  Future<bool> confirm(String reason) async => true;
}

/// A service gets the name picked for it, one per service. There is no name on
/// the account: changing one here can't reach any other service.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final decisions = <Map<String, dynamic>>[];
  final created = <Map<String, dynamic>>[];
  var takenKeys = <String>[];
  Map<String, dynamic>? selected;
  final identity = CryptoService().generateIdentity(commonName: 'Ada');

  Future<http.Response> server(http.Request request) async {
    http.Response json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    );
    final path = request.url.path;
    if (path == '/oidc/authorize/app') {
      return json({
        'ticket': 'tkt0123456789',
        'client': 'https://game.example',
        'account': {'email': 'ada@home.test'},
        'scopes': [
          {'scope': 'profile', 'value': ''},
        ],
        'links': <Object>[],
        'nameOptions': [
          {'kind': 'identity', 'id': 'id1', 'value': 'Ada Lovelace'},
          {
            'kind': 'record',
            'id': 'r1',
            'key': 'gamer_tag',
            'label': 'Gamer tag',
            'value': 'xXAdaXx',
          },
        ],
        'nameSelected': ?selected,
      });
    }
    if (path == '/oidc/authorize/consent') {
      decisions.add(jsonDecode(request.body) as Map<String, dynamic>);
      return json({'redirect': 'https://game.example/callback?code=c'});
    }
    if (path == '/api/collections/records/records') {
      if (request.method == 'POST') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        created.add(body);
        return json({'id': 'new1', ...body});
      }
      return json({
        'items': [
          for (final k in takenKeys) {'id': k, 'key': k},
        ],
      });
    }
    if (path == '/api/collections/identities/records') {
      return json({
        'items': [
          {
            'id': 'id1',
            'name': 'Ada Lovelace',
            'certificate': identity.publicKeyPem,
            'fingerprint': 'cd' * 32,
            'user': 'u1',
            'workspace': 'w1',
            'isPrimary': true,
            'status': 'active',
          },
        ],
      });
    }
    return json({'items': <Object>[]});
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      'identity_priv_id1': identity.privateKeyPem,
    });
    await Stores.init(
      httpClient: MockClient(server),
      unlock: _AlwaysUnlocked(),
    );
    runInAction(
      () => Stores.auth.currentUser = User.fromJson({
        'id': 'u1',
        'email': 'ada@home.test',
        'activeWorkspace': 'w1',
      }),
    );
    decisions.clear();
    created.clear();
    takenKeys = [];
    selected = null;
  });

  final request = SignInRequest.fromQuery({
    'client_id': 'https://game.example',
    'redirect_uri': 'https://game.example/callback',
    'response_type': 'code',
    'scope': 'openid profile',
    'state': 'st-1',
    'nonce': 'n-1',
    'code_challenge': 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
    'code_challenge_method': 'S256',
  })!;

  Future<void> show(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.light),
        home: SignInApprovalScreen(request: request),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pick(WidgetTester tester, String item) async {
    await tester.tap(find.text(item).last);
    await tester.pumpAndSettle();
  }

  testWidgets('nothing picked: the name stays private', (tester) async {
    await show(tester);
    expect(find.text('No name'), findsOneWidget);
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(decisions.single['scopes'], isEmpty);
    expect(decisions.single.containsKey('name'), isFalse);
  });

  testWidgets('a vault entry can be the name for this service', (tester) async {
    await show(tester);
    await pick(tester, 'xXAdaXx');
    expect(find.textContaining('Stored in the vault'), findsOneWidget);
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(decisions.single['scopes'], ['profile']);
    expect(decisions.single['name'], {'kind': 'record', 'id': 'r1'});
    expect(created, isEmpty);
  });

  testWidgets('it starts on the name given last time', (tester) async {
    selected = {'kind': 'identity', 'id': 'id1'};
    await show(tester);
    expect(find.text('Ada Lovelace'), findsWidgets);
    expect(find.text('No name'), findsNothing);
    expect(find.textContaining('Stored in the vault'), findsNothing);
  });

  testWidgets('a new name becomes an entry of its own, once confirmed', (
    tester,
  ) async {
    takenKeys = ['name_game_example'];
    await show(tester);
    await tester.tap(find.widgetWithText(TextField, 'New name'));
    await tester.pumpAndSettle();

    final signIn = find.widgetWithText(FilledButton, 'Sign in');
    expect(tester.widget<FilledButton>(signIn).onPressed, isNull);
    expect(created, isEmpty);

    await tester.enterText(
      find.widgetWithText(TextField, 'New name'),
      ' xXAdaXx ',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(created.single['key'], 'name_game_example_2');
    expect(created.single['value'], 'xXAdaXx');
    expect(created.single['label'], 'Name on game.example');
    expect(created.single['user'], 'u1');
    expect(created.single['workspace'], 'w1');
    expect(decisions.single['name'], {'kind': 'record', 'id': 'new1'});
    expect(decisions.single['scopes'], ['profile']);
  });

  test('a service reads the name it gets from what the row points at', () {
    final fromIdentity = SignInService.fromJson({
      'id': 's',
      'nameIdentity': 'id1',
      'expand': {
        'nameIdentity': {'name': 'Ada Lovelace'},
      },
    });
    expect(fromIdentity.name, 'Ada Lovelace');
    expect(fromIdentity.nameRecord, '');

    final fromEntry = SignInService.fromJson({
      'id': 's',
      'nameRecord': 'r1',
      'expand': {
        'nameRecord': {'value': 'xXAdaXx'},
      },
    });
    expect(fromEntry.name, 'xXAdaXx');
    expect(fromEntry.nameRecord, 'r1');

    // Its entry lives in another workspace: nothing to show, but still known.
    final elsewhere = SignInService.fromJson({'id': 's', 'nameRecord': 'r1'});
    expect(elsewhere.name, '');
    expect(elsewhere.nameRecord, 'r1');
  });
}
