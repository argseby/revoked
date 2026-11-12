import 'package:material_ui/material_ui.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobx/mobx.dart';
import 'package:revoked_app/core/models/api_key.dart';
import 'package:revoked_app/core/models/attestation.dart';
import 'package:revoked_app/core/models/attestation_check.dart';
import 'package:revoked_app/core/models/connection.dart';
import 'package:revoked_app/core/models/invite.dart';
import 'package:revoked_app/core/models/feature.dart';
import 'package:revoked_app/core/models/request.dart';
import 'package:revoked_app/core/models/section.dart';
import 'package:revoked_app/core/models/user.dart';
import 'package:revoked_app/core/models/webhook.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/app_button.dart';
import 'package:revoked_app/core/widgets/app_detail.dart';
import 'package:revoked_app/features/settings/view/settings_pages.dart';
import 'package:revoked_app/features/shell/view/account_menu.dart';
import 'package:revoked_app/core/models/tool_client.dart';
import 'package:revoked_app/core/design/spacing.dart';
import 'package:revoked_app/core/widgets/tool_proposal_alert.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Every destination has to fit every window the app runs in: a small phone,
/// a phone on its side, a tablet and a desktop. An overflow throws, so simply
/// visiting each place at each size is the check.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sizes = {
    'small phone': Size(320, 640),
    'phone': Size(375, 812),
    'phone on its side': Size(812, 375),
    'tablet': Size(768, 1024),
    'desktop': Size(1280, 800),
  };

  Future<GoRouter> signedIn(
    WidgetTester tester,
    Size size, {
    List<String>? features,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await Stores.init(
      httpClient: MockClient((_) async => http.Response('{}', 404)),
    );
    runInAction(() => Stores.auth.currentUser = null);
    final router = AppRouter.create(Stores.auth);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    runInAction(
      () => Stores.auth.currentUser = User.fromJson({
        'id': 'u1',
        'email': 'ada@example.com',
        'activeWorkspace': 'w1',
        'features': ?features,
      }),
    );
    await tester.pumpAndSettle();
    return router;
  }

  /// The catalogue and two sections with long names, for the pages that
  /// show what a tool or a key may do.
  void withAccessFixtures() {
    runInAction(() {
      Stores.invites.catalogue.addAll([
        for (final (key, label) in [
          ('vault:read', 'Read vault'),
          ('vault:write', 'Manage vault'),
          ('shares:read', 'View shares'),
          ('shares:manage', 'Manage shares'),
        ])
          InvitePermission(
            key: key,
            label: label,
            description: 'A description long enough to wrap on a phone.',
            membersOnly: key.startsWith('vault:'),
            scopes: [key],
          ),
      ]);
      Stores.vault.sections.addAll([
        for (final id in ['s1', 's2'])
          Section(
            id: id,
            key: id,
            name: 'A section with a name long enough to wrap $id',
            records: const [],
            user: 'u1',
            workspace: 'w1',
          ),
      ]);
    });
  }

  /// Every place, shown or hidden: a hidden one still opens from a link, with
  /// a notice above it, and has to fit with that notice too.
  Future<void> visitEverywhere(
    WidgetTester tester,
    GoRouter router,
    String reason,
  ) async {
    for (final destination in [
      ...AppRoutes.allDestinations,
      AppRoutes.settings,
      AppRoutes.settingsPage(SettingsPage.features.slug),
    ]) {
      router.go(destination);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$destination $reason');
    }
  }

  for (final MapEntry(key: name, value: size) in sizes.entries) {
    testWidgets('every destination fits a $name', (tester) async {
      final router = await signedIn(tester, size);
      await visitEverywhere(tester, router, 'with everything on');
    });

    /// Each feature off in turn takes a tab away; the rest close up.
    for (final off in Feature.values) {
      testWidgets('every destination fits a $name with ${off.key} off', (
        tester,
      ) async {
        final router = await signedIn(
          tester,
          size,
          features: [
            for (final f in Feature.values)
              if (f != off) f.key,
          ],
        );
        expect(
          AppRoutes.destinations.length,
          lessThanOrEqualTo(AppRoutes.allDestinations.length),
        );
        await visitEverywhere(tester, router, 'with ${off.key} off');
      });
    }

    testWidgets('every destination fits a $name with only the vault', (
      tester,
    ) async {
      final router = await signedIn(tester, size, features: const []);
      expect(AppRoutes.destinations, [AppRoutes.vault]);
      await visitEverywhere(tester, router, 'with only the vault');
    });
  }

  group('phone bottom bar', () {
    NavigationBar bar(WidgetTester tester) =>
        tester.widget<NavigationBar>(find.byType(NavigationBar));

    testWidgets('holds no more tabs than a small phone can label', (
      tester,
    ) async {
      await signedIn(tester, sizes['small phone']!);
      expect(bar(tester).destinations.length, lessThanOrEqualTo(5));
    });

    testWidgets('reaches the rest through More, which then shows as current', (
      tester,
    ) async {
      final router = await signedIn(tester, sizes['phone']!);
      expect(find.text('Contacts'), findsNothing);

      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      expect(find.text('Attestations'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      await tester.tap(find.text('Contacts'));
      await tester.pumpAndSettle();

      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        AppRoutes.contacts,
      );
      expect(bar(tester).selectedIndex, bar(tester).destinations.length - 1);
    });

    testWidgets('a deep link past the bar still has a current tab', (
      tester,
    ) async {
      final router = await signedIn(tester, sizes['phone']!);
      router.go(AppRoutes.attestations);
      await tester.pumpAndSettle();
      expect(bar(tester).selectedIndex, bar(tester).destinations.length - 1);
    });

    testWidgets('a feature turned off takes its tab away; the rest close up', (
      tester,
    ) async {
      await signedIn(
        tester,
        sizes['phone']!,
        features: ['requests', 'attestations', 'contacts'],
      );
      final labels = [
        for (final d in bar(tester).destinations)
          (d as NavigationDestination).label,
      ];
      expect(labels, ['Vault', 'Requests', 'Attestations', 'Contacts', 'More']);
      // Settings still waits under More, however few tabs there are.
      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);
    });
  });

  testWidgets('a phone\'s sub-page has its back arrow, not the avatar', (
    tester,
  ) async {
    final router = await signedIn(tester, sizes['phone']!);
    for (final root in [
      AppRoutes.settings,
      AppRoutes.vault,
      AppRoutes.shared,
    ]) {
      router.go(root);
      await tester.pumpAndSettle();
      expect(find.byType(AccountMenu), findsOneWidget, reason: root);
    }

    for (final page in [
      AppRoutes.settingsPage(SettingsPage.encryption.slug),
      AppRoutes.signInServiceFor('s1'),
      AppRoutes.recordDetailFor('r1'),
      AppRoutes.shareDetailFor('l1'),
      AppRoutes.requestDetailFor('q1'),
    ]) {
      router.go(page);
      await tester.pumpAndSettle();
      expect(find.byType(AccountMenu), findsNothing, reason: page);
      expect(find.byTooltip('Back'), findsOneWidget, reason: page);
    }
  });

  testWidgets('New stays off a phone\'s detail pages', (tester) async {
    final router = await signedIn(tester, sizes['phone']!);
    expect(find.byType(FloatingActionButton), findsNothing);

    router.go(AppRoutes.recordDetailFor('r1'));
    await tester.pumpAndSettle();
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  group('a sheet with no close button', () {
    Future<void> openPicker(WidgetTester tester, Size size) async {
      await signedIn(tester, size);
      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create something new'));
      await tester.pumpAndSettle();
    }

    for (final name in ['small phone', 'phone']) {
      testWidgets('leaves the page showing above it on a $name', (
        tester,
      ) async {
        final size = sizes[name]!;
        await openPicker(tester, size);
        expect(tester.takeException(), isNull);
        expect(
          tester.getRect(find.byType(BottomSheet)).top,
          greaterThanOrEqualTo(size.height * 0.3 - 0.5),
        );
      });
    }

    testWidgets('closes on a tap above it', (tester) async {
      await openPicker(tester, sizes['phone']!);
      await tester.tapAt(const Offset(187, 40));
      await tester.pumpAndSettle();
      expect(find.text('Create something new'), findsNothing);
    });

    testWidgets('still fits above the keyboard', (tester) async {
      await openPicker(tester, sizes['phone']!);
      tester.view.viewInsets = const FakeViewPadding(bottom: 340);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.getRect(find.byType(BottomSheet)).bottom,
        sizes['phone']!.height,
      );
    });
  });

  group('tool proposal notice', () {
    for (final entry in sizes.entries) {
      testWidgets('fits on a ${entry.key}', (tester) async {
        tester.view.physicalSize = entry.value;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: ToolProposalAlert(
                  proposer: ToolProposer(
                    client: 'https://a-rather-long-tool-name.example.com',
                    name: 'A rather long assistant name, 40 chars',
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('webhook pages', () {
    for (final entry in sizes.entries) {
      testWidgets('fit on a ${entry.key}', (tester) async {
        final router = await signedIn(tester, entry.value);
        final day = [
          for (var i = 0; i < 24; i++)
            {
              'start': DateTime.utc(2026, 11, 3, i).toIso8601String(),
              'delivered': 40 + i,
              'failed': i == 15 ? 20 : 1,
              'p50Ms': 120,
              'p95Ms': i == 15 ? 2400 : 300,
            },
        ];
        runInAction(() {
          final store = Stores.webhooks;
          store.endpoints.add(
            WebhookEndpoint.fromJson({
              'id': 'h1',
              'url': 'https://a-rather-long-integration-host.example.com/hooks/revoked/f3a9c1d2',
              'description': 'CRM sync for the onboarding team',
              'events': ['link.revoked', 'response.submitted'],
              'enabled': true,
              'failingSince': '2026-11-01T09:00:00Z',
              'stats': {'succeeded': 1204, 'failed': 37, 'pending': 3},
              'series': day,
            }),
          );
          store.metrics['h1'] = WebhookMetrics.fromJson({
            'range': '24h',
            'buckets': day,
            'deliveries': 1241,
            'firstTry': 1190,
            'retrying': 3,
            'p95Ms': 1420,
            'codes': {'2xx': 1204, '4xx': 12, '5xx': 20, 'none': 5},
            'events': [
              {'type': 'response.submitted', 'count': 800},
              {'type': 'link.revoked', 'count': 441},
            ],
          });
          store.eventTypes.addAll([
            const WebhookEventType(
              type: 'response.submitted',
              group: 'Answers',
              description: 'Someone answered a request, or answered it again.',
              noisy: false,
            ),
            const WebhookEventType(
              type: 'link.revoked',
              group: 'Shares',
              description: 'A share was revoked or deleted.',
              noisy: false,
            ),
          ]);
          store.testType = 'response.submitted';
          store.deliveries['h1'] = [
            WebhookDelivery.fromJson({
              'id': 'd1',
              'endpoint': 'h1',
              'type': 'attestation.revoked',
              'status': 'pending',
              'attempts': 4,
              'lastStatus': 503,
              'nextAttemptAt': '2026-11-03T10:00:00Z',
              'created': '2026-11-03T09:00:00Z',
            }),
          ];
        });
        router.go(AppRoutes.webhooks);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        router.go(AppRoutes.webhookFor('h1'));
        await tester.pumpAndSettle();
        expect(find.text('Deliveries'), findsWidgets);
        expect(find.text('Activity'), findsOneWidget);
        expect(find.text('Response time'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.ensureVisible(find.text('attestation.revoked'));
        await tester.tap(find.text('attestation.revoked'));
        await tester.pumpAndSettle();
        expect(find.text('What was sent'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('connected tool page', () {
    for (final entry in sizes.entries) {
      testWidgets('fits on a ${entry.key}', (tester) async {
        final router = await signedIn(tester, entry.value);
        const name = 'A rather long assistant name, 40 chars';
        runInAction(() {
          final store = Stores.connections;
          store.connections.add(
            Connection.fromJson({
              'id': 'c1',
              'clientId': 'https://a-rather-long-tool-name.example.com',
              'clientName': name,
              'expiresAt': '2099-01-01 00:00:00.000Z',
              'allowVaultRead': true,
            }),
          );
          store.requestsByConnection['c1'] = [
            DataRequest.fromJson({
              'id': 'q1',
              'label': 'Applications for the flat on the third floor',
              'status': 'active',
              'maxResponses': 20,
              'responseCount': 11,
              'expiresAt': '2099-01-01 00:00:00.000Z',
            }),
          ];
          store.attestationsByConnection['c1'] = [
            Attestation.fromJson({
              'id': 'a1',
              'type': 'https://schemas.example.com/a-long-membership-type',
              'status': 'revoked',
              'subjectName': 'Somebody with a long name',
            }),
          ];
          store.checksByConnection['c1'] = [
            AttestationCheck.fromJson({
              'id': 'k1',
              'type': 'membership',
              'status': 'open',
              'expiresAt': '2099-01-01 00:00:00.000Z',
            }),
          ];
        });
        router.go(AppRoutes.connectedToolFor('c1'));
        await tester.pumpAndSettle();
        expect(find.text('Checks from $name'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('with its permissions and sections fits on a ${entry.key}', (
        tester,
      ) async {
        final router = await signedIn(tester, entry.value);
        const name = 'A rather long assistant name, 40 chars';
        withAccessFixtures();
        runInAction(() {
          Stores.connections.connections.add(
            Connection.fromJson({
              'id': 'c1',
              'clientId': 'https://a-rather-long-tool-name.example.com',
              'clientName': name,
              'expiresAt': '2099-01-01 00:00:00.000Z',
              'scopes': ['link:read', 'link:update'],
              'vaultAccess': 'write',
              'section': 's1',
              'sections': ['s2'],
            }),
          );
        });
        router.go(AppRoutes.connectedToolFor('c1'));
        await tester.pumpAndSettle();
        expect(find.text('Vault sections'), findsOneWidget);
        expect(find.text('Its own'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('connected tools, and API keys on their own page', () {
    for (final entry in sizes.entries) {
      testWidgets('list fits on a ${entry.key}', (tester) async {
        final router = await signedIn(tester, entry.value);
        withAccessFixtures();
        runInAction(() {
          Stores.connections.connections.add(
            Connection.fromJson({
              'id': 'c1',
              'clientId': 'https://a-rather-long-tool-name.example.com',
              'clientName': 'A rather long assistant name, 40 chars',
              'expiresAt': '2099-01-01 00:00:00.000Z',
              'vaultAccess': 'read',
              'sections': ['s1', 's2'],
            }),
          );
          Stores.apiKeys.apiKeys.add(
            ApiKey.fromJson({
              'id': 'k1',
              'label': 'A rather long name for an import script',
              'user': 'u1',
              'workspace': 'w1',
              'scopes': ['link:read'],
              'vaultAccess': 'write',
              'sections': ['s1'],
              'expiresAt': '2099-01-01 00:00:00.000Z',
            }),
          );
        });
        router.go(AppRoutes.connectedTools);
        await tester.pumpAndSettle();
        expect(find.text('API keys'), findsNothing);
        expect(tester.takeException(), isNull);
        router.go(AppRoutes.apiKeys);
        await tester.pumpAndSettle();
        expect(find.text('API keys'), findsWidgets);
        expect(tester.takeException(), isNull);
      });

      testWidgets('new key form with sections fits on a ${entry.key}', (
        tester,
      ) async {
        final router = await signedIn(tester, entry.value);
        router.go(AppRoutes.apiKeys);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('New API key'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Custom'));
        await tester.tap(find.text('Custom'));
        await tester.pumpAndSettle();
        withAccessFixtures();
        runInAction(() => Stores.apiKeys.toggleDraftScope('vault:write', true));
        await tester.pumpAndSettle();
        expect(find.text('Sections', skipOffstage: false), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets(
        'connect screen asking for a section fits on a ${entry.key}',
        (tester) async {
          final router = await signedIn(tester, entry.value);
          withAccessFixtures();
          router.go(
            Uri(
              path: AppRoutes.connect,
              queryParameters: const ConnectRequest(
                client: 'https://a-rather-long-tool-name.example.com',
                name: 'A rather long assistant name, 40 chars',
                redirect: 'https://a-rather-long-tool-name.example.com/cb',
                state: 'st',
                challenge: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
                section: true,
                permissions: ['shares:manage', 'vault:write'],
                reasons: ToolReasons(
                  section: 'To keep the documents you upload with you',
                  permissions: 'To share the documents you upload',
                ),
              ).toQuery(),
            ).toString(),
          );
          await tester.pumpAndSettle();
          expect(find.text('Vault section'), findsOneWidget);
          expect(find.text('Manage'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  });

  group('detail header', () {
    Future<void> pumpHeader(
      WidgetTester tester, {
      required double width,
      required int icons,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: AppDetailHeader(
                  title: 'IBAN',
                  primaryAction: AppButton(
                    key: const Key('primary'),
                    label: 'Copy',
                    onTap: () {},
                  ),
                  secondaryActions: [
                    for (var i = 0; i < icons; i++)
                      AppButton(
                        key: Key('icon$i'),
                        icon: Icons.share,
                        tooltip: 'Action $i',
                        onTap: () {},
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    double top(WidgetTester tester, String key) =>
        tester.getTopLeft(find.byKey(Key(key))).dy;

    testWidgets('keeps one row while the main action has room', (tester) async {
      await pumpHeader(tester, width: 343, icons: 2);
      expect(top(tester, 'icon0'), top(tester, 'primary'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('moves the icons under it when it would be squeezed', (
      tester,
    ) async {
      await pumpHeader(tester, width: 343, icons: 4);
      expect(top(tester, 'icon0'), greaterThan(top(tester, 'primary')));
      // At full width, the main action's label is never cut short.
      expect(tester.getSize(find.byKey(const Key('primary'))).width, 335);
      expect(tester.takeException(), isNull);
    });
  });
}
