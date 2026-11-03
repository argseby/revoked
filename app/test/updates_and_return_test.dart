import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobx/mobx.dart';
import 'package:revoked_app/core/models/user.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/features/settings/store/updates_store.dart';
import 'package:revoked_app/features/settings/view/settings_pages.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('update check', () {
    UpdatesStore store(
      http.Response Function() reply, {
      String? server = 'v0.36.0',
      List<Uri>? asked,
    }) => UpdatesStore(
      httpClient: MockClient((req) async {
        asked?.add(req.url);
        return reply();
      }),
      serverVersion: () => server,
    );

    test('a newer server release is reported', () async {
      final s = store(
        () => http.Response('{"app":"v0.37.0","server":"v0.37.0"}', 200),
      );
      await s.checkIfDue();
      expect(s.latestServer, 'v0.37.0');
      expect(s.serverUpdate, isTrue);
    });

    test('a server on the newest release has nothing to report', () async {
      final s = store(
        () => http.Response('{"app":"v0.36.0","server":"v0.36.0"}', 200),
      );
      await s.checkIfDue();
      expect(s.serverUpdate, isFalse);
    });

    test('a development build of the app is never told to update', () async {
      final s = store(
        () => http.Response('{"app":"v9.0.0","server":"v9.0.0"}', 200),
      );
      await s.checkIfDue();
      expect(s.appUpdate, isFalse);
    });

    test('no answer reports nothing', () async {
      final s = store(() => http.Response('not found', 404));
      await s.checkIfDue();
      expect(s.latestServer, isNull);
      expect(s.serverUpdate, isFalse);
    });

    test('an unknown server version is never behind', () async {
      final s = store(
        () => http.Response('{"app":"v0.37.0","server":"v0.37.0"}', 200),
        server: null,
      );
      await s.checkIfDue();
      expect(s.serverUpdate, isFalse);
    });

    test('asks once, not on every visit', () async {
      final asked = <Uri>[];
      final s = store(
        () => http.Response('{"app":"v0.37.0","server":"v0.37.0"}', 200),
        asked: asked,
      );
      await s.checkIfDue();
      await s.checkIfDue();
      expect(asked, hasLength(1));
    });
  });

  group('back arrow', () {
    Future<GoRouter> signedIn(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      await Stores.init(
        httpClient: MockClient((_) async => http.Response('{}', 404)),
      );
      final router = AppRouter.create(Stores.auth);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      runInAction(
        () => Stores.auth.currentUser = User.fromJson({
          'id': 'u1',
          'email': 'ada@example.com',
          'activeWorkspace': 'w1',
        }),
      );
      await tester.pumpAndSettle();
      return router;
    }

    String at(GoRouter router) =>
        router.routerDelegate.currentConfiguration.uri.path;

    Future<void> back(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Back').first);
      await tester.pumpAndSettle();
    }

    testWidgets('templates opened from settings returns to settings', (
      tester,
    ) async {
      final router = await signedIn(tester);
      router.go(AppRoutes.settings);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Templates'));
      await tester.tap(find.text('Templates'));
      await tester.pumpAndSettle();
      expect(at(router), AppRoutes.templates);
      await back(tester);
      expect(at(router), AppRoutes.settings);
    });

    testWidgets('templates opened from requests returns to requests', (
      tester,
    ) async {
      final router = await signedIn(tester);
      router.go('${AppRoutes.templates}?from=${AppRoutes.requests}');
      await tester.pumpAndSettle();
      await back(tester);
      expect(at(router), AppRoutes.requests);
    });

    testWidgets('templates reached directly falls back to settings', (
      tester,
    ) async {
      final router = await signedIn(tester);
      router.go(AppRoutes.templates);
      await tester.pumpAndSettle();
      await back(tester);
      expect(at(router), AppRoutes.settings);
    });

    testWidgets('a return address outside the app is ignored', (tester) async {
      final router = await signedIn(tester);
      router.go('${AppRoutes.templates}?from=//example.com/x');
      await tester.pumpAndSettle();
      await back(tester);
      expect(at(router), AppRoutes.settings);
    });
  });

  group('create buttons', () {
    for (final (page, label) in [
      (SettingsPage.identities, 'New identity'),
      (SettingsPage.workspaces, 'New workspace'),
      (SettingsPage.apiKeys, 'New API key'),
      (SettingsPage.webhooks, 'New webhook'),
    ]) {
      testWidgets('${page.title} creates from the top bar', (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        SharedPreferences.setMockInitialValues({});
        FlutterSecureStorage.setMockInitialValues({});
        await Stores.init(
          httpClient: MockClient((_) async => http.Response('{}', 404)),
        );
        final router = AppRouter.create(Stores.auth);
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        runInAction(
          () => Stores.auth.currentUser = User.fromJson({
            'id': 'u1',
            'email': 'ada@example.com',
            'activeWorkspace': 'w1',
          }),
        );
        await tester.pumpAndSettle();
        router.go(page.route);
        await tester.pumpAndSettle();
        expect(find.byTooltip(label), findsOneWidget);
        await tester.tap(find.byTooltip(label));
        await tester.pumpAndSettle();
        expect(find.text('Cancel'), findsWidgets);
      });
    }
  });
}
