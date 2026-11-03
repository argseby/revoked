import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobx/mobx.dart';
import 'package:revoked_app/core/models/feature.dart';
import 'package:revoked_app/core/models/user.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/feature_notice.dart';
import 'package:revoked_app/features/requests/view/public_request_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A link can land on a feature the person turned off. The page still opens,
/// says why it is not in the navigation, and turns the feature on in one
/// tap - never a dead end.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final saved = <List<dynamic>>[];

  Future<http.Response> server(http.Request request) async {
    http.Response json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );
    if (request.url.path == '/api/account/features') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      saved.add(body['features'] as List<dynamic>);
      return json({'features': body['features']});
    }
    return json({}, 404);
  }

  Future<GoRouter> signedIn(
    WidgetTester tester, {
    required List<String> features,
  }) async {
    saved.clear();
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await Stores.init(httpClient: MockClient(server));
    runInAction(() => Stores.auth.currentUser = null);
    final router = AppRouter.create(Stores.auth);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    runInAction(
      () => Stores.auth.currentUser = User.fromJson({
        'id': 'u1',
        'email': 'ada@example.com',
        'activeWorkspace': 'w1',
        'features': features,
      }),
    );
    await tester.pumpAndSettle();
    return router;
  }

  test('every shell place and settings topic names its feature', () {
    expect(featureForLocation('/overview'), Feature.sharing);
    expect(featureForLocation('/shared/l1'), Feature.sharing);
    expect(featureForLocation('/requests/q1/sheet'), Feature.requests);
    expect(featureForLocation('/vault/templates'), Feature.requests);
    expect(
      featureForLocation('/attestations?tab=issued'),
      Feature.attestations,
    );
    expect(featureForLocation('/settings/identities'), Feature.attestations);
    expect(featureForLocation('/contacts'), Feature.contacts);
    expect(featureForLocation('/settings/connected-tools'), Feature.tools);
    expect(featureForLocation('/settings/signed-in/s1'), Feature.tools);
    expect(featureForLocation('/settings/api-keys'), Feature.developer);
    expect(featureForLocation('/vault'), isNull);
    expect(featureForLocation('/settings'), isNull);
    expect(featureForLocation('/settings/features'), isNull);
  });

  testWidgets(
    'a request link with Requests off opens, and offers to turn it on',
    (tester) async {
      final router = await signedIn(tester, features: []);
      router.go('/r/abc123');
      await tester.pumpAndSettle();

      expect(find.byType(PublicRequestScreen), findsOneWidget);
      expect(find.text('Requests is off'), findsOneWidget);

      await tester.tap(find.text('Turn on Requests'));
      await tester.pumpAndSettle();

      expect(saved.single, ['requests']);
      expect(Stores.features.visible(Feature.requests), isTrue);
      expect(find.text('Requests is off'), findsNothing);
      expect(find.byType(PublicRequestScreen), findsOneWidget);
    },
  );

  testWidgets('a hidden shell place and a hidden settings page say so too', (
    tester,
  ) async {
    final router = await signedIn(tester, features: ['sharing']);
    router.go(AppRoutes.contacts);
    await tester.pumpAndSettle();
    expect(find.text('Contacts is off'), findsOneWidget);
    expect(find.text('Turn on Contacts'), findsOneWidget);

    // API keys are listed with connected tools; the old address leads there.
    router.go(AppRoutes.apiKeys);
    await tester.pumpAndSettle();
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      AppRoutes.connectedTools,
    );
    expect(find.text('Connected tools is off'), findsOneWidget);

    router.go(AppRoutes.vault);
    await tester.pumpAndSettle();
    expect(find.textContaining(' is off'), findsNothing);
  });

  testWidgets('with nothing but the vault, home is the vault', (tester) async {
    final router = await signedIn(tester, features: []);
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      AppRoutes.vault,
    );
    expect(AppRoutes.destinations, [AppRoutes.vault]);
    expect(find.text('Shares'), findsNothing);
    expect(find.text('Requests'), findsNothing);
    expect(find.text('More'), findsOneWidget);

    router.go(AppRoutes.overview);
    await tester.pumpAndSettle();
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      AppRoutes.vault,
    );
  });
}
