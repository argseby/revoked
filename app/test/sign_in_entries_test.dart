import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobx/mobx.dart';
import 'package:revoked_app/core/models/sign_in_request.dart';
import 'package:revoked_app/core/models/user.dart';
import 'package:revoked_app/core/models/workspace.dart';
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

/// A service asks for a key from the vault. The person answers with an entry,
/// a new value, or nothing, from the workspace they choose here.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final decisions = <Map<String, dynamic>>[];
  final created = <Map<String, dynamic>>[];
  final opened = <String>[];
  var takenKeys = <String>[];
  var workspace = 'w1';
  var options = <Map<String, dynamic>>[];
  var sections = <Map<String, dynamic>>[];
  final identity = CryptoService().generateIdentity(commonName: 'Ada');

  final gamerTag = {
    'id': 'r1abcdefghijklm',
    'key': 'gamer_tag',
    'label': 'Gamer tag',
    'preview': 'xXAdaXx',
    'type': 'text',
  };
  final workEntry = {
    'id': 'r2abcdefghijklm',
    'key': 'showdown_name',
    'label': 'Work name',
    'preview': 'AdaAtWork',
    'type': 'text',
  };

  Future<http.Response> server(http.Request request) async {
    http.Response json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    );
    final path = request.url.path;
    if (path == '/oidc/authorize/app') {
      opened.add(workspace);
      return json({
        'ticket': 'tkt-$workspace',
        'client': 'https://game.example',
        'account': {'email': 'ada@home.test'},
        'scopes': <Object>[],
        'signers': ['id1'],
        'sections': sections,
        'links': [
          {
            'key': 'showdown_name',
            'options': workspace == 'w1' ? options : [workEntry],
          },
        ],
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
    if (path == '/api/collections/users/auth-refresh') {
      return json({
        'token': 'tok',
        'record': {
          'id': 'u1',
          'email': 'ada@home.test',
          'activeWorkspace': workspace,
        },
      });
    }
    if (path == '/api/collections/users/records/u1') {
      if (request.method == 'PATCH') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        workspace = body['activeWorkspace'] as String;
      }
      return json({
        'id': 'u1',
        'email': 'ada@home.test',
        'activeWorkspace': workspace,
      });
    }
    if (path == '/api/collections/identities/records') {
      // Only the active workspace's: the key on this device is for an identity
      // the list doesn't show after switching.
      if (workspace != 'w1') return json({'items': <Object>[]});
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
    await Stores.api.saveAuthState('session', {'id': 'u1'});
    runInAction(
      () => Stores.auth.currentUser = User.fromJson({
        'id': 'u1',
        'email': 'ada@home.test',
        'activeWorkspace': 'w1',
      }),
    );
    decisions.clear();
    created.clear();
    opened.clear();
    takenKeys = [];
    workspace = 'w1';
    options = [gamerTag];
    sections = [];
  });

  final request = SignInRequest.fromQuery({
    'client_id': 'https://game.example',
    'redirect_uri': 'https://game.example/callback',
    'response_type': 'code',
    'scope': 'openid',
    'state': 'st-1',
    'nonce': 'n-1',
    'code_challenge': 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
    'code_challenge_method': 'S256',
    'claims': '{"userinfo":{"revoked_links":{"values":["showdown_name"]}}}',
  })!;

  Future<void> show(
    WidgetTester tester, {
    Size size = const Size(900, 2400),
  }) async {
    tester.view.physicalSize = size * 2;
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

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.scrollUntilVisible(
      find.text(text).last,
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text(text).last);
    await tester.pumpAndSettle();
  }

  Future<void> typeNew(WidgetTester tester, String text) async {
    final field = find.widgetWithText(TextField, 'New value');
    await tester.scrollUntilVisible(
      field,
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(field, text);
    await tester.pumpAndSettle();
  }

  testWidgets('a new value is saved under the key the service asked for', (
    tester,
  ) async {
    await show(tester);
    await tester.tap(find.byType(TextField).last);
    await tester.pumpAndSettle();

    final signIn = find.widgetWithText(FilledButton, 'Sign in');
    expect(tester.widget<FilledButton>(signIn).onPressed, isNull);
    expect(created, isEmpty);

    await typeNew(tester, ' Ada ');
    expect(find.text('Ada'), findsOneWidget);
    await tester.tap(signIn);
    await tester.pumpAndSettle();

    expect(created.single['key'], 'showdown_name');
    expect(created.single['value'], 'Ada');
    expect(created.single['workspace'], 'w1');
    expect(decisions.single['links'], {'showdown_name': 'new1'});
    expect(decisions.single['created'], ['new1']);
  });

  testWidgets('a key already in use keeps its value', (tester) async {
    takenKeys = ['showdown_name'];
    options = [
      {...gamerTag, 'key': 'showdown_name'},
    ];
    await show(tester);
    await typeNew(tester, 'Ada');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(created.single['key'], 'showdown_name_2');
    expect(decisions.single['links'], {'showdown_name': 'new1'});
  });

  testWidgets('nothing is picked until the person picks it', (tester) async {
    await show(tester);
    expect(find.text('Nothing'), findsOneWidget);
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(decisions.single['links'], isEmpty);
  });

  testWidgets('the switch turns a pick off and brings it back', (tester) async {
    options = [
      {...gamerTag, 'key': 'showdown_name'},
    ];
    await show(tester);
    expect(find.text('Nothing'), findsNothing);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('Nothing'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('Nothing'), findsNothing);
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(decisions.single['links'], {'showdown_name': gamerTag['id']});
  });

  testWidgets('an entry under another key says an alias will be added', (
    tester,
  ) async {
    options = [
      {...gamerTag, 'key': 'player_name'},
    ];
    await show(tester);
    expect(find.textContaining('alias'), findsNothing);
    await tapText(tester, 'xXAdaXx');
    expect(find.textContaining('alias “showdown_name”'), findsOneWidget);
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(created, isEmpty);
    expect(decisions.single['links'], {'showdown_name': gamerTag['id']});
    expect(decisions.single['created'], isEmpty);
  });

  testWidgets('a file can’t be an alias, so none is promised', (tester) async {
    options = [
      {...gamerTag, 'key': 'player_name', 'preview': '', 'type': 'file'},
    ];
    await show(tester);
    await tapText(tester, 'Gamer tag');
    expect(find.textContaining('alias'), findsNothing);
  });

  group('a big vault', () {
    setUp(() {
      options = [
        for (var i = 1; i <= 100; i++)
          {
            'id': 'rec${i.toString().padLeft(12, '0')}',
            'key': 'note_$i',
            'label': 'Note $i',
            'preview': 'Value $i',
            'type': 'text',
          },
      ];
      sections = [
        {
          'id': 's1',
          'key': 'gaming',
          'name': 'Gaming',
          'records': [
            for (var i = 1; i <= 20; i++) 'rec${i.toString().padLeft(12, '0')}',
          ],
        },
        {
          'id': 's2',
          'key': 'signin_steam_example',
          'name': 'steam.example',
          'records': ['rec${21.toString().padLeft(12, '0')}'],
        },
      ];
    });

    testWidgets('goes in folders, a few at a time', (tester) async {
      await show(tester);
      expect(find.text('Value 1'), findsNothing);
      await tapText(tester, 'Browse vault');

      expect(find.text('Gaming'), findsOneWidget);
      expect(find.text('20 entries'), findsOneWidget);
      expect(find.text('Sign-in · steam.example'), findsOneWidget);
      expect(find.text('Not in a section'), findsOneWidget);
      expect(find.text('79 entries'), findsOneWidget);
      expect(find.text('Value 1'), findsNothing);

      await tester.tap(find.text('Gaming'));
      await tester.pumpAndSettle();
      expect(find.text('Value 8'), findsOneWidget);
      expect(find.text('Value 9'), findsNothing);
      await tester.tap(find.text('Show all 20'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Value 20'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Value 20'));
      await tester.pumpAndSettle();
      expect(find.text('Browse vault'), findsOneWidget);
      expect(find.text('Value 20'), findsWidgets);
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(decisions.single['links'], {
        'showdown_name': 'rec${20.toString().padLeft(12, '0')}',
      });
    });

    testWidgets('a folder can be left again', (tester) async {
      await show(tester);
      await tapText(tester, 'Browse vault');
      await tester.tap(find.text('Gaming'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Back to vault'));
      await tester.pumpAndSettle();
      expect(find.text('20 entries'), findsOneWidget);
    });

    testWidgets('search looks in every folder and says where', (tester) async {
      await show(tester);
      await tapText(tester, 'Browse vault');
      await tester.enterText(
        find.widgetWithText(TextField, 'Search vault'),
        'Value 21',
      );
      await tester.pumpAndSettle();
      expect(find.text('Note 21 · Sign-in · steam.example'), findsOneWidget);
      expect(find.text('Gaming'), findsNothing);
    });

    testWidgets('a search that finds nothing can become a new value', (
      tester,
    ) async {
      await show(tester);
      await tapText(tester, 'Browse vault');
      await tester.enterText(
        find.widgetWithText(TextField, 'Search vault'),
        'Ada',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create “Ada”'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(created.single['value'], 'Ada');
      expect(decisions.single['links'], {'showdown_name': 'new1'});
    });
  });

  testWidgets('with one workspace there is nothing to choose', (tester) async {
    await show(tester);
    expect(find.byTooltip('Switch workspace'), findsNothing);
  });

  group('with two workspaces', () {
    Future<void> showBoth(WidgetTester tester, {Size? size}) async {
      await show(tester, size: size ?? const Size(900, 2400));
      runInAction(() {
        Stores.settings.workspaces
          ..clear()
          ..addAll([
            for (final (id, name) in [('w1', 'Home'), ('w2', 'Work')])
              Workspace(id: id, name: name, slug: id),
          ]);
      });
      await tester.pumpAndSettle();
    }

    testWidgets('switching opens the request again in that workspace', (
      tester,
    ) async {
      options = [
        {...gamerTag, 'key': 'player_name'},
      ];
      await showBoth(tester);
      await tapText(tester, 'xXAdaXx');
      await tester.tap(find.byTooltip('Switch workspace').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Work').last);
      // The switch reloads every store, and the spinner runs until it's done.
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)),
      );
      await tester.pumpAndSettle();

      expect(workspace, 'w2');
      expect(opened, ['w1', 'w2']);
      expect(find.text('AdaAtWork'), findsWidgets);
      expect(find.textContaining('alias'), findsNothing);

      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      expect(decisions.single['ticket'], 'tkt-w2');
      expect(decisions.single['links'], {'showdown_name': workEntry['id']});
    });

    testWidgets('switching inside the browser keeps it open on the new vault', (
      tester,
    ) async {
      options = [
        for (var i = 1; i <= 5; i++)
          {
            'id': 'rec${i.toString().padLeft(12, '0')}',
            'key': 'note_$i',
            'label': 'Note $i',
            'preview': 'Value $i',
            'type': 'text',
          },
      ];
      await showBoth(tester);
      await tapText(tester, 'Browse vault');
      await tester.tap(find.byTooltip('Switch workspace').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Work').last);
      // While it loads: the placeholder has to fit the browser's scroll view.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)),
      );
      await tester.pumpAndSettle();

      expect(workspace, 'w2');
      expect(find.text('Search vault'), findsOneWidget);
      expect(find.text('Not in a section'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    for (final size in const [
      Size(320, 640),
      Size(375, 812),
      Size(812, 375),
      Size(768, 1024),
      Size(1280, 800),
    ]) {
      testWidgets('nothing overflows at ${size.width}×${size.height}', (
        tester,
      ) async {
        await showBoth(tester, size: size);
        await typeNew(tester, 'Ada');
        await tapText(tester, 'Browse vault');
        expect(tester.takeException(), isNull);
      });
    }
  });
}
