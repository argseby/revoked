import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobx/mobx.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:revoked_app/core/models/user.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/router/resume_location.dart';
import 'package:revoked_app/core/services/crypto_service.dart';
import 'package:revoked_app/core/services/device_unlock.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/theme/app_theme.dart';

class _Unlock implements DeviceUnlock {
  @override
  Future<bool> confirm(String reason) async => true;
}

/// A link that arrives has to show up. The router keeps a page alive for as
/// long as its route stays the same, so a second sign-in used to sit unseen
/// behind the first one's "Signed in to …".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final identity = CryptoService().generateIdentity(commonName: 'Ada');
  final opened = <String>[];
  final paths = <String>[];

  Future<http.Response> server(http.Request request) async {
    http.Response json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    );
    paths.add(request.url.path);
    switch (request.url.path) {
      case '/oidc/authorize/app':
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final client = body['params']['client_id'] as String;
        opened.add(client);
        return json({
          'ticket': 'tkt0123456789',
          'client': client,
          'account': {'email': 'ada@home.test'},
          'scopes': <Object>[],
          'links': <Object>[],
        });
      case '/oidc/authorize/consent':
        return json({'redirect': 'https://game.example/callback?code=c1'});
      case '/api/collections/identities/records':
        return json({
          'items': [
            {
              'id': 'id1',
              'name': 'Ada',
              'certificate': identity.publicKeyPem,
              'fingerprint': 'cd' * 32,
              'user': 'u',
              'workspace': 'w',
              'isPrimary': true,
              'status': 'active',
            },
          ],
        });
    }
    return json({'items': <Object>[]});
  }

  String signIn(String host) => Uri(
    path: '/signin',
    queryParameters: {
      'client_id': 'https://$host',
      'redirect_uri': 'https://$host/callback',
      'response_type': 'code',
      'scope': 'openid',
      'state': 'st-1',
      'code_challenge': 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
      'code_challenge_method': 'S256',
    },
  ).toString();

  User signedIn(String workspace) => User.fromJson({
    'id': 'u1',
    'email': 'ada@home.test',
    'activeWorkspace': workspace,
  });

  Future<GoRouter> start(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final router = AppRouter.create(Stores.auth);
    addTearDown(router.dispose);
    runInAction(() {
      Stores.auth.currentUser = signedIn('w1');
      Stores.auth.isInitialized = true;
    });
    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.build(Brightness.light),
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  Future<void> open(WidgetTester tester, GoRouter router, String link) async {
    AppRouter.openLink(router, link);
    await tester.pumpAndSettle();
  }

  Future<void> approve(WidgetTester tester) async {
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Signed in to'), findsOneWidget);
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      'identity_priv_id1': identity.privateKeyPem,
    });
    await Stores.init(httpClient: MockClient(server), unlock: _Unlock());
    ResumeLocation.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/url_launcher'),
          (call) async => true,
        );
    opened.clear();
    paths.clear();
  });

  testWidgets('a new sign-in replaces a finished one', (tester) async {
    final router = await start(tester);
    await open(tester, router, signIn('game.example'));
    await approve(tester);

    await open(tester, router, signIn('other.example'));
    expect(opened, ['https://game.example', 'https://other.example']);
    expect(find.text('Sign in to other.example'), findsOneWidget);
    expect(find.textContaining('Signed in to'), findsNothing);
  });

  testWidgets('the same sign-in asked for again starts over', (tester) async {
    final router = await start(tester);
    await open(tester, router, signIn('game.example'));
    await approve(tester);

    await open(tester, router, signIn('game.example'));
    expect(opened, ['https://game.example', 'https://game.example']);
    expect(find.text('Sign in to game.example'), findsOneWidget);
  });

  testWidgets('a new link closes what was open over the last one', (
    tester,
  ) async {
    final router = await start(tester);
    await open(tester, router, signIn('game.example'));
    showDialog<void>(
      context: AppRouter.rootNavigatorKey.currentContext!,
      builder: (_) => const Text('Still open'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Still open'), findsOneWidget);

    await open(tester, router, signIn('other.example'));
    expect(find.text('Still open'), findsNothing);
    expect(find.text('Sign in to other.example'), findsOneWidget);
  });

  testWidgets('a new share link loads the new share', (tester) async {
    final router = await start(tester);
    await open(tester, router, '/s/firstslug');
    paths.clear();

    await open(tester, router, '/s/secondslug');
    expect(paths.where((p) => p.contains('secondslug')), isNotEmpty);
  });

  testWidgets('an ask opens its form while Attestations is showing', (
    tester,
  ) async {
    final router = await start(tester);
    router.go(AppRoutes.attestations);
    await tester.pumpAndSettle();
    expect(find.text('Filled in from a request'), findsNothing);

    final ask = Uri(
      path: AppRoutes.attestations,
      queryParameters: {'type': 'membership', 'for': 'ab' * 32},
    ).toString();
    await open(tester, router, ask);
    expect(find.text('Filled in from a request'), findsOneWidget);
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      AppRoutes.attestations,
    );
    expect(router.routerDelegate.currentConfiguration.uri.query, isEmpty);
  });

  testWidgets('a session change does not restart the screen', (tester) async {
    final router = await start(tester);
    await open(tester, router, signIn('game.example'));
    await approve(tester);

    runInAction(() => Stores.auth.currentUser = signedIn('w2'));
    await tester.pumpAndSettle();
    expect(opened, ['https://game.example']);
    expect(find.textContaining('Signed in to'), findsOneWidget);
  });
}
