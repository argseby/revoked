import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobx/mobx.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:revoked_app/core/models/tool_client.dart';
import 'package:revoked_app/core/models/works_with.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/theme/app_theme.dart';
import 'package:revoked_app/features/works_with/store/works_with_store.dart';
import 'package:revoked_app/features/works_with/view/works_with_chip.dart';
import 'package:revoked_app/features/works_with/view/works_with_screen.dart';

Map<String, dynamic> _entry({
  String slug = 'example',
  String origin = 'https://tool.example.org',
  String name = 'Example',
  List<String> does = const ['share', 'connect'],
  List<String> categories = const ['work'],
  List<String> keys = const ['full_name'],
  List<String> permissions = const ['revoke_links'],
  bool verified = false,
  bool builtByRevoked = false,
}) => {
  'slug': slug,
  'origin': origin,
  'name': name,
  'description': {'en': 'An example tool.', 'de': 'Ein Beispielwerkzeug.'},
  'operator': {'name': 'Example GmbH', 'security': 'mailto:sec@example.org'},
  'privacy_policy': 'https://tool.example.org/privacy',
  'self_hostable': false,
  'servers': <String>[],
  'languages': ['de', 'en'],
  'pricing': 'paid',
  'categories': categories,
  'does': does,
  'proposes': {
    'shares': {'templates': <String>[], 'keys': keys},
  },
  'permissions': [
    for (final p in permissions)
      {
        'key': p,
        'reason': {'en': 'Because.', 'de': 'Darum.'},
      },
  ],
  'stores': {'en': 'Nothing.', 'de': 'Nichts.'},
  'built_by_revoked': builtByRevoked,
  'verified': verified,
  'status': 'listed',
  'reviewed': '2026-11-09',
};

String _catalog(List<Map<String, dynamic>> services) =>
    jsonEncode({'schema': 1, 'services': services});

ConnectRequest _connect(Map<String, String> extra) => ConnectRequest.fromQuery({
  'client': 'https://tool.example.org',
  'name': 'Example',
  'redirect': 'https://tool.example.org/back',
  'state': 'abc',
  'challenge': 'a' * 43,
  ...extra,
})!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('catalog', () {
    test('the bundled catalog parses and lists the project\'s own tools', () {
      final body = File('assets/works_with/catalog.json').readAsStringSync();
      final catalog = WorksWithCatalog.parse(body);
      expect(catalog, isNotNull);
      final slugs = catalog!.services.map((s) => s.slug);
      expect(slugs, containsAll(['notfallkarte', 'mietunterlagen']));
      // Built by Revoked counts as verified without a proof file.
      for (final s in catalog.services.where((s) => s.builtByRevoked)) {
        expect(s.verified, isTrue, reason: s.slug);
      }
    });

    test('an unknown schema is refused, a bad entry is skipped', () {
      expect(WorksWithCatalog.parse('{"schema": 2, "services": []}'), isNull);
      expect(WorksWithCatalog.parse('not json'), isNull);
      final c = WorksWithCatalog.parse(
        _catalog([
          _entry(),
          _entry(slug: 'bad', origin: 'http://insecure.example.org'),
          _entry(slug: 'dup', name: 'Duplicate'),
        ]),
      )!;
      expect(c.services.map((s) => s.slug), ['example']);
    });

    test('matching is by origin only, normalised', () {
      final c = WorksWithCatalog.parse(_catalog([_entry()]))!;
      expect(c.forOrigin('https://tool.example.org')?.slug, 'example');
      expect(c.forOrigin('https://TOOL.example.org/')?.slug, 'example');
      expect(c.forOrigin('https://tool.example.org.evil.test'), isNull);
      expect(c.forOrigin('https://other.example.org'), isNull);
      expect(c.forOrigin(''), isNull);
    });

    test('unverified unless the entry says so or Revoked built it', () {
      final c = WorksWithCatalog.parse(
        _catalog([
          _entry(slug: 'a', origin: 'https://a.example.org'),
          _entry(slug: 'b', origin: 'https://b.example.org', verified: true),
          _entry(
            slug: 'c',
            origin: 'https://c.revoked.link',
            builtByRevoked: true,
          ),
        ]),
      )!;
      expect([for (final s in c.services) s.verified], [false, true, true]);
    });

    test('descriptions follow the language, English by default', () {
      const t = LocalizedText(en: 'Hello', de: 'Hallo');
      expect(t.forLanguage('de'), 'Hallo');
      expect(t.forLanguage('fr'), 'Hello');
      expect(const LocalizedText(en: 'Hello').forLanguage('de'), 'Hello');
    });
  });

  group('what a tool asks beyond its listing', () {
    final service = WorksWithService.fromJson(
      _entry(permissions: ['revoke_links', 'shares:read']),
    )!;

    test('a request within the listing has nothing extra', () {
      expect(
        service.undeclaredForConnect(_connect({'permissions': 'shares:read'})),
        isEmpty,
      );
    });

    test('vault reading, a section and permissions are counted', () {
      final extra = service.undeclaredForConnect(
        _connect({
          'vault': 'read',
          'section': '1',
          'permissions': 'shares:read,requests:manage',
        }),
      );
      expect(extra, ['section', 'read_vault', 'requests:manage']);
    });

    test('record keys outside the listing are counted', () {
      expect(service.undeclaredKeys(['full_name', 'iban']), ['iban']);
    });

    test('access is the strongest switch declared', () {
      ServiceAccess access(List<String> p) =>
          WorksWithService.fromJson(_entry(permissions: p))!.access;
      expect(access(['revoke_links']), ServiceAccess.linksOnly);
      expect(access(['section']), ServiceAccess.ownSection);
      expect(access(['section', 'read_vault']), ServiceAccess.readsVault);
    });
  });

  group('store', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('starts from the bundled copy and keeps it when offline', () async {
      final store = WorksWithStore(
        httpClient: MockClient((_) async => throw const SocketException('x')),
        loadAsset: (_) async => _catalog([_entry()]),
      );
      await store.loadLocal();
      expect(store.services.single.slug, 'example');

      await store.refreshIfDue();
      expect(store.services.single.slug, 'example');
      expect(store.refreshFailed, isTrue);
    });

    test('a fetched copy replaces the bundled one and is cached', () async {
      var asked = 0;
      final store = WorksWithStore(
        httpClient: MockClient((_) async {
          asked++;
          return http.Response(
            _catalog([_entry(slug: 'newer', name: 'Newer')]),
            200,
          );
        }),
        loadAsset: (_) async => _catalog([_entry()]),
      );
      await store.loadLocal();
      await store.refreshIfDue();
      expect(store.services.single.slug, 'newer');

      // At most once a day.
      await store.refreshIfDue();
      expect(asked, 1);

      // A later start finds the fetched copy before asking again.
      final next = WorksWithStore(
        httpClient: MockClient((_) async => http.Response('', 500)),
        loadAsset: (_) async => _catalog([_entry()]),
      );
      await next.loadLocal();
      expect(next.services.single.slug, 'newer');
    });

    test('a broken download keeps the list shown', () async {
      final store = WorksWithStore(
        httpClient: MockClient((_) async => http.Response('{"schema":9}', 200)),
        loadAsset: (_) async => _catalog([_entry()]),
      );
      await store.loadLocal();
      await store.refreshIfDue();
      expect(store.services.single.slug, 'example');
    });
  });

  group('screens', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      await Stores.init(
        httpClient: MockClient(
          (_) async => http.Response('{"items": []}', 200),
        ),
      );
      final catalog = WorksWithCatalog.parse(
        _catalog([
          _entry(),
          _entry(
            slug: 'card',
            origin: 'https://card.revoked.link',
            name: 'Card',
            categories: ['health'],
            builtByRevoked: true,
          ),
          _entry(
            slug: 'game',
            origin: 'https://game.example.org',
            name: 'Game',
            does: ['sign_in'],
            categories: ['games'],
            permissions: [],
            keys: [],
          ),
        ]),
      )!;
      runInAction(() => Stores.worksWith.catalog = catalog);
    });

    Future<void> pump(WidgetTester tester, Widget child) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(Brightness.light),
          home: Scaffold(body: child),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the list shows every service with its mark', (tester) async {
      await pump(tester, const WorksWithScreen());
      expect(find.text('Example'), findsOneWidget);
      expect(find.text('Card'), findsOneWidget);
      expect(find.text('Game'), findsOneWidget);
      expect(find.text('Unverified'), findsNWidgets(2));
      expect(find.text('Listed'), findsWidgets);
    });

    testWidgets('search narrows the list', (tester) async {
      await pump(tester, const WorksWithScreen());
      await tester.enterText(find.byType(TextField).first, 'game');
      await tester.pumpAndSettle();
      expect(find.text('Game'), findsOneWidget);
      expect(find.text('Example'), findsNothing);
      expect(find.text('Card'), findsNothing);
    });

    testWidgets('a card names the access and what the service does', (
      tester,
    ) async {
      await pump(tester, const WorksWithScreen());
      // None of the three declares a section or vault reading.
      expect(find.text('Never reads the vault'), findsNWidgets(3));
      expect(find.text('tool.example.org'), findsOneWidget);
      expect(find.text('Sign in'), findsOneWidget);
      expect(find.text('Built by Revoked'), findsOneWidget);
    });

    testWidgets('a chip narrows the list to what a service does', (
      tester,
    ) async {
      await pump(tester, const WorksWithScreen());
      expect(find.text('All 3'), findsOneWidget);
      expect(find.text('Share 2'), findsOneWidget);
      // A kind with no service has no chip.
      expect(find.textContaining('Prove'), findsNothing);

      await tester.tap(find.text('Sign in 1'));
      await tester.pumpAndSettle();
      expect(find.text('Game'), findsOneWidget);
      expect(find.text('Example'), findsNothing);
      expect(find.text('Card'), findsNothing);

      await tester.tap(find.text('All 3'));
      await tester.pumpAndSettle();
      expect(find.text('Example'), findsOneWidget);
    });

    testWidgets('the cards fit a phone', (tester) async {
      await pump(tester, const WorksWithScreen());
      tester.view.physicalSize = const Size(720, 4800);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Game'), findsOneWidget);
    });

    testWidgets('the chip shows only for a listed address', (tester) async {
      await pump(
        tester,
        const Column(
          children: [
            WorksWithChip(origin: 'https://card.revoked.link'),
            WorksWithChip(origin: 'https://unlisted.example.org'),
          ],
        ),
      );
      expect(find.text('Listed'), findsOneWidget);
      expect(find.text('Unverified'), findsNothing);
    });

    testWidgets('the mismatch names the extra switches by label', (
      tester,
    ) async {
      final service = Stores.worksWith.bySlug('example')!;
      await pump(
        tester,
        WorksWithMismatchAlert(service: service, extra: const ['read_vault']),
      );
      expect(find.text('Not covered by the listing'), findsOneWidget);
      expect(find.textContaining('without: Read vault'), findsOneWidget);
    });
  });
}
