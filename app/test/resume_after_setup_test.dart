import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobx/mobx.dart';
import 'package:revoked_app/core/models/user.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/router/resume_location.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/features/auth/view/login_screen.dart';
import 'package:revoked_app/features/onboarding/store/onboarding_store.dart';
import 'package:revoked_app/features/onboarding/view/workspace_onboarding_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Someone new opens a tool's proposal before they have an account. Signing
/// up and setting up a workspace used to end on the vault, with the proposal
/// gone - they had to go back to the tool and start it again.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const proposal = '/p?label=Notfallkarte%20Max&keys=full_name';

  String location(GoRouter router) =>
      router.routerDelegate.currentConfiguration.uri.toString();

  group('resume location', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      ResumeLocation.clear();
    });

    test('holds a proposal, a connect request and an invite', () {
      for (final l in [proposal, '/connect?client=x', '/i/tok?o=a.example']) {
        ResumeLocation.hold(l);
        expect(ResumeLocation.take(), l);
      }
    });

    test('ignores anything else', () {
      ResumeLocation.hold('/vault');
      expect(ResumeLocation.peek(), isNull);
    });

    test('a plain navigation does not replace a held proposal', () {
      ResumeLocation.hold(proposal);
      ResumeLocation.hold('/settings');
      expect(ResumeLocation.peek(), proposal);
    });

    test('resumes once', () {
      ResumeLocation.hold(proposal);
      expect(ResumeLocation.take(), proposal);
      expect(ResumeLocation.take(), isNull);
    });

    test('survives a restart, but not for ever', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({
        'resume_location': jsonEncode({'location': proposal, 'at': now}),
      });
      await ResumeLocation.load();
      expect(ResumeLocation.peek(), proposal);

      ResumeLocation.clear();
      final stale = now - ResumeLocation.ttl.inMilliseconds - 1000;
      SharedPreferences.setMockInitialValues({
        'resume_location': jsonEncode({'location': proposal, 'at': stale}),
      });
      await ResumeLocation.load();
      expect(ResumeLocation.peek(), isNull);
    });
  });

  group('suggested names', () {
    test('the name is read from the address', () {
      expect(nameFromEmail('max.mustermann@example.com'), 'Max Mustermann');
      expect(nameFromEmail('ada_lovelace@x.org'), 'Ada Lovelace');
      expect(nameFromEmail('jo-ann+post@x.org'), 'Jo Ann');
      expect(nameFromEmail('max92@x.org'), 'Max92');
      expect(nameFromEmail('@x.org'), '');
      expect(nameFromEmail(''), '');
    });

    test('prefill suggests both names once per address', () {
      final store = OnboardingStore();
      store.prefill('ada.lovelace@example.com');
      expect(store.nameController.text, defaultWorkspaceName);
      expect(store.identityNameController.text, 'Ada Lovelace');

      // What the person typed survives a rebuild.
      store.nameController.text = 'Family';
      store.prefill('ada.lovelace@example.com');
      expect(store.nameController.text, 'Family');

      // Another account starts from fresh suggestions.
      store.prefill('max@example.com');
      expect(store.nameController.text, defaultWorkspaceName);
      expect(store.identityNameController.text, 'Max');
    });
  });

  testWidgets('a proposal opened signed out is waiting after setup', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await Stores.init(
      httpClient: MockClient((_) async => http.Response('{}', 404)),
    );
    ResumeLocation.clear();
    final auth = Stores.auth;

    final router = AppRouter.create(auth);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    router.go(proposal);
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Sign in or create an account first'), findsOneWidget);

    // Signed up: an account, no workspace yet.
    runInAction(
      () => auth.currentUser = User.fromJson({
        'id': 'u1',
        'email': 'max.mustermann@example.com',
        'activeWorkspace': '',
      }),
    );
    await tester.pumpAndSettle();
    expect(find.byType(WorkspaceOnboardingScreen), findsOneWidget);
    expect(find.text('Personal'), findsOneWidget);
    expect(find.text('Max Mustermann'), findsOneWidget);
    expect(ResumeLocation.peek(), proposal);

    // The workspace exists: the proposal opens, not the vault.
    runInAction(
      () => auth.currentUser = User.fromJson({
        'id': 'u1',
        'email': 'max.mustermann@example.com',
        'activeWorkspace': 'w1',
      }),
    );
    await tester.pumpAndSettle();
    expect(location(router), proposal);
    expect(ResumeLocation.peek(), isNull);
  });
}
