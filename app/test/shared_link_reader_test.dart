import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:revoked_app/core/crypto/sealed_formats.dart';
import 'package:revoked_app/core/router/held_link_keys.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/utils/deep_links.dart';
import 'package:revoked_app/features/shares/store/shared_link_reader.dart';
import 'package:revoked_app/features/shares/view/public_share_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final vector =
      jsonDecode(
            File(
              'test/fixtures/sealing_link_read_vectors.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final keyText = vector['linkKey'] as String;
  final key = SealedFormats.parseLinkKey(keyText)!;
  final entry = vector['entry'] as Map<String, dynamic>;
  final content = vector['content'] as Map<String, dynamic>;
  const plain = {
    'id': 'plain0000000001',
    'key': 'note',
    'label': 'Note',
    'type': 'text',
    'value': 'A plain value',
  };

  test('a pasted web address keeps its key outside the router location', () {
    final uri = DeepLinks.fromWebAddress(
      Uri.parse('https://example.com:8443/s/contractor#k=$keyText'),
    )!;
    expect(DeepLinks.linkKey(uri), key);
    expect(DeepLinks.locationFor(uri), '/s/contractor?o=example.com%3A8443');
    HeldLinkKeys.holdFrom(uri);
    expect(
      HeldLinkKeys.take(slug: 'contractor', origin: 'other.example'),
      isNull,
    );
    HeldLinkKeys.holdFrom(uri);
    expect(
      HeldLinkKeys.take(slug: 'contractor', origin: 'example.com:8443'),
      key,
    );
    expect(
      HeldLinkKeys.take(slug: 'contractor', origin: 'example.com:8443'),
      isNull,
    );
    HeldLinkKeys.holdFrom(uri);
    HeldLinkKeys.holdFrom(Uri.parse('revoked://s/example.com:8443/contractor'));
    expect(
      HeldLinkKeys.take(slug: 'contractor', origin: 'example.com:8443'),
      isNull,
    );
  });

  test('tampering never produces a value, and plain entries stay readable', () {
    for (final change in <Map<String, dynamic>>[
      {'key': 'another_key'},
      {'sealedVersion': 7},
      {'sealedValue': '***'},
      {'viewerWrap': '***'},
    ]) {
      final data = SharedLinkReader.open({
        'records': [
          {...entry, ...change},
          plain,
        ],
      }, key);
      final records = data['records'] as List;
      expect(records[0]['value'], isNull);
      expect(ClosedEntry.of(records[0]), isNotNull);
      expect(records[1], plain);
    }
  });

  for (final state in ['open', 'incomplete', 'replaced', 'unavailable']) {
    testWidgets('signed-out share screen: $state', (tester) async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final seen = <http.Request>[];
      await tester.runAsync(() async {
        await Stores.init(
          httpClient: MockClient((request) async {
            seen.add(request);
            if (request.url.path == '/api/public/links/contractor') {
              return http.Response(
                jsonEncode(
                  request.method == 'GET'
                      ? {'label': 'Contractor'}
                      : {
                          'label': 'Contractor',
                          'records': [
                            if (state == 'unavailable')
                              {...entry, 'unavailable': true}
                            else
                              entry,
                            plain,
                          ],
                        },
                ),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            return http.Response(
              '{}',
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        while (!Stores.auth.isInitialized) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      });
      expect(Stores.auth.isAuthenticated, isFalse);
      HeldLinkKeys.hold(
        slug: 'contractor',
        key: switch (state) {
          'incomplete' => null,
          'replaced' => Uint8List(32),
          _ => key,
        },
      );
      tester.view.physicalSize = const Size(1100, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      GoRouter? router;
      if (state == 'open') {
        router = AppRouter.create(Stores.auth);
        router.go('revoked://s/contractor#k=$keyText');
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      } else {
        await tester.pumpWidget(
          const MaterialApp(home: PublicShareScreen(shareSlug: 'contractor')),
        );
      }
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(find.text('A plain value'), findsOneWidget);
      final records = Stores.shares.shareData!['records'] as List;
      if (state == 'open') {
        expect(records[0]['value'], content['v']);
        expect(find.text(content['l'] as String), findsOneWidget);
        expect(records[0]['type'], content['t']);
        expect(records[0]['format'], content['f']);
        expect(records[0].containsKey('viewerWrap'), isFalse);
      } else {
        final why = ClosedEntry.values.firstWhere((s) => s.name == state);
        expect(find.text(why.title), findsOneWidget);
        expect(records[0].containsKey('value'), isFalse);
      }
      final requests = seen.map((r) => '${r.url} ${r.body}').join('\n');
      expect(requests, isNot(contains(keyText)));
      expect(requests, isNot(contains(content['v'])));
      expect(
        seen.where(
          (r) =>
              r.url.path == '/api/public/links/contractor' &&
              r.method == 'POST',
        ),
        hasLength(1),
      );
      if (router != null) {
        expect(
          router.routerDelegate.currentConfiguration.uri.toString(),
          '/s/contractor',
        );
      }
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getKeys().map((k) => '${prefs.get(k)}').join(),
        isNot(contains(keyText)),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      router?.dispose();
      Stores.shares.resetShareView();
      expect(Stores.shares.shareLinkKey, isNull);
    });
  }
}
