import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:revoked_app/core/models/share_proposal.dart';
import 'package:revoked_app/core/models/tool_client.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/theme/app_theme.dart';
import 'package:revoked_app/features/connections/view/connect_screen.dart';
import 'package:revoked_app/features/shares/view/share_proposal_screen.dart';

/// A proposal names keys the vault may not hold yet. Everything missing has to
/// be fillable on the proposal itself — typed or attached — never by leaving
/// for the vault and coming back.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A server holding one of the owner's records, and someone else's answer
  // under a key the proposal asks for.
  final records = <Map<String, dynamic>>[];
  final authorized = <Map<String, dynamic>>[];
  final createdLinks = <Map<String, dynamic>>[];
  final launched = <String>[];
  final sections = <Map<String, dynamic>>[];
  var nextId = 0;

  Map<String, dynamic> record(
    String key,
    String value, {
    String label = '',
    String requestedBy = '',
  }) => {
    'id': 'r${nextId++}',
    'key': key,
    'value': value,
    'label': label,
    'type': 'text',
    'format': 'default',
    'user': 'u',
    'workspace': 'w',
    'requestedBy': requestedBy,
  };

  const template = {
    'id': 't1',
    'name': 'Tenant application',
    'workspace': '',
    'schema': {
      'records': [
        {'key': 'full_name', 'label': 'Full name', 'type': 'text'},
        {'key': 'net_income', 'label': 'Monthly net income', 'type': 'number'},
        {'key': 'has_pets', 'label': 'Pets', 'type': 'boolean'},
      ],
      'sections': [
        {
          'key': 'documents',
          'name': 'Documents',
          'records': [
            {
              'key': 'proof_of_income',
              'label': 'Proof of income',
              'type': 'file',
            },
          ],
        },
      ],
    },
  };

  /// Answers the handful of routes the screen touches, applying the record
  /// filter the way the server would for key and requestedBy.
  Future<http.Response> server(http.Request request) async {
    final path = request.url.path;
    http.Response json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    );

    if (path == '/api/collections/records/records') {
      if (request.method == 'POST') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final created = {
          ...record(body['key'] as String, body['value'] as String),
          'label': body['label'],
          'type': body['type'],
        };
        records.add(created);
        return json(created);
      }
      final filter = request.url.queryParameters['filter'] ?? '';
      final keys = RegExp(
        r'key = "([a-z0-9_-]+)"',
      ).allMatches(filter).map((m) => m.group(1)).toSet();
      final ownOnly = filter.contains('requestedBy = ""');
      return json({
        'items': [
          for (final r in records)
            if ((keys.isEmpty || keys.contains(r['key'])) &&
                (!ownOnly || r['requestedBy'] == ''))
              r,
        ],
      });
    }
    if (path.startsWith('/api/collections/records/records/') &&
        request.method == 'PATCH') {
      final id = path.split('/').last;
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final r = records.firstWhere((r) => r['id'] == id);
      r.addAll(body);
      return json(r);
    }
    if (path.startsWith('/api/collections/records/records/') &&
        request.method == 'DELETE') {
      records.removeWhere((r) => r['id'] == path.split('/').last);
      return http.Response('', 204);
    }
    if (path == '/api/collections/sections/records') {
      if (request.method == 'POST') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final created = {...body, 'id': 's${sections.length}'};
        sections.add(created);
        return json(created);
      }
      return json({'items': sections});
    }
    if (path.startsWith('/api/collections/sections/records/')) {
      return json(sections.first);
    }
    if (path == '/api/connections/authorize') {
      authorized.add(jsonDecode(request.body) as Map<String, dynamic>);
      return json({'code': 'one-time-code', 'connectionId': 'conn1'});
    }
    if (path == '/api/collections/links/records' && request.method == 'POST') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      createdLinks.add(body);
      return json({
        ...body,
        'id': 'link${createdLinks.length}',
        'user': 'u',
        'workspace': 'w',
      });
    }
    if (path == '/api/collections/templates/records') {
      return json({
        'items': [template],
      });
    }
    return json({'items': <Object>[]});
  }

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await Stores.init(httpClient: MockClient(server));
    // The way back to the tool opens a browser; here it is only recorded.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/url_launcher'),
          (call) async {
            launched.add((call.arguments as Map)['url'] as String);
            return true;
          },
        );
  });

  setUp(() {
    records
      ..clear()
      ..add(record('full_name', 'Max Muster', label: 'Full name'))
      // An applicant's answer to one of the owner's own requests.
      ..add(record('net_income', '9999', requestedBy: 'someone'));
    sections.clear();
  });

  Future<void> open(WidgetTester tester, ShareProposal proposal) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.light),
        home: ShareProposalScreen(proposal: proposal),
      ),
    );
    await tester.pumpAndSettle();
  }

  const proposal = ShareProposal(
    label: 'Musterstr. 5',
    keys: ['full_name', 'net_income', 'proof_of_income', 'guarantor'],
    stamp: 'Nur für Wohnungsbewerbung Musterstr. 5',
    days: 14,
    purpose: 'application',
    from: 'Mietunterlagen',
    template: 'Tenant application',
  );

  testWidgets(
    'missing items are added in place; a tool is connected and handed the link',
    (tester) async {
      await open(tester, proposal);

      expect(find.text('Musterstr. 5'), findsOneWidget);
      // Held: a ticked row with its value.
      expect(find.text('Max Muster'), findsOneWidget);
      // Someone else's answer is not the owner's net income.
      expect(find.text('9999'), findsNothing);
      expect(find.text('Monthly net income'), findsOneWidget);
      // Described by the template: one input of the right kind.
      expect(find.text('Add file'), findsNWidgets(2));
      // Not in the template: offered both as text and as a file.
      expect(find.text('Guarantor'), findsOneWidget);
      expect(find.text('Add'), findsNWidgets(2));
      expect(find.textContaining('open the link again'), findsNothing);

      // A value added here joins the link straight away. net_income is the first missing row with a text input.
      await tester.tap(find.text('Add').first);
      await tester.pumpAndSettle();
      expect(find.text('Save'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '3200');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('3200'), findsOneWidget);
      // Saved as the owner's own record, not over the received answer.
      expect(
        records.where(
          (r) => r['key'] == 'net_income' && r['requestedBy'] == '',
        ),
        hasLength(1),
      );
      expect(
        records.singleWhere((r) => r['requestedBy'] == 'someone')['value'],
        '9999',
      );
      // Filed in the template's section.
      expect(sections.single['key'], 'tenant_application');
      // One fewer thing missing.
      expect(find.text('Add'), findsOneWidget);

      // A value already held can be changed right here, in place.
      final before = records.length;
      await tester.tap(find.byTooltip('Edit Full name'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        'Max Muster',
      );
      await tester.enterText(find.byType(TextField), 'Max Mustermann');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Max Mustermann'), findsOneWidget);
      expect(records, hasLength(before));
      expect(
        records.singleWhere((r) => r['key'] == 'full_name')['value'],
        'Max Mustermann',
      );

      // A yes-or-no field is chosen, not typed.
      await tester.pumpWidget(const SizedBox());
      await open(
        tester,
        const ShareProposal(
          label: 'Musterstr. 5',
          keys: ['full_name', 'has_pets'],
          from: 'Mietunterlagen',
          template: 'Tenant application',
        ),
      );
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();
      final pets = records.singleWhere((r) => r['key'] == 'has_pets');
      expect(pets['value'], 'true');
      expect(pets['type'], 'boolean');
      // Shown in words, and changed the same way.
      expect(find.text('Yes'), findsOneWidget);
      await tester.tap(find.byTooltip('Edit Pets'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('No'));
      await tester.pumpAndSettle();
      expect(pets['value'], 'false');
      expect(find.text('No'), findsOneWidget);

      // A held value can be deleted from the vault: asked first, then the
      // key is missing again.
      await tester.tap(find.byTooltip('Delete Pets'));
      await tester.pumpAndSettle();
      expect(records.where((r) => r['key'] == 'has_pets'), hasLength(1));
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(records.where((r) => r['key'] == 'has_pets'), isEmpty);
      expect(find.text('Add'), findsOneWidget);
      expect(find.text('Max Mustermann'), findsOneWidget);

      // A tool that names itself: connected on the way, and handed the link.
      const tool = 'https://mietunterlagen.example.com';
      await tester.pumpWidget(const SizedBox());
      await open(
        tester,
        ShareProposal(
          label: 'Hauptstr. 1',
          keys: const ['full_name'],
          stamp: 'Nur für Wohnungsbewerbung Hauptstr. 1',
          days: 14,
          purpose: 'application',
          from: 'Mietunterlagen',
          template: 'Tenant application',
          client: tool,
          redirect: '$tool/',
          state: 'st-1',
          challenge: 'c' * 43,
          ref: 'flat-7',
        ),
      );
      expect(find.text('Connect Mietunterlagen'), findsOneWidget);
      // The owner's own choices sit in their own section, ticked to start.
      expect(find.text('You decide'), findsOneWidget);
      expect(find.text('Revoke links it proposed'), findsOneWidget);
      expect(find.text('Receive the links it proposed'), findsOneWidget);
      // The connection is decided first; the link is reviewed after it.
      expect(find.textContaining('will receive this link'), findsNothing);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      // Allowed for the connection, so the link goes to the tool without
      // being asked about again.
      expect(find.textContaining('will receive this link'), findsOneWidget);
      await tester.ensureVisible(find.text('Create link'));
      await tester.tap(find.text('Create link'));
      await tester.pumpAndSettle();

      // Connected first, with the tool's own challenge and way back …
      expect(authorized.single['clientId'], tool);
      expect(authorized.single['challenge'], 'c' * 43);
      expect(authorized.single['allowRevoke'], true);
      expect(authorized.single['allowHandOver'], true);
      // … then the link, tied to that connection, tagged, and handed over.
      expect(createdLinks.single['connection'], 'conn1');
      expect(createdLinks.single['ref'], 'flat-7');
      expect(createdLinks.single['handedOver'], true);
      // Straight back to the tool, carrying only what the app adds.
      final back = Uri.parse(launched.single);
      expect(back.origin, tool);
      expect(back.queryParameters['state'], 'st-1');
      expect(back.queryParameters['status'], 'created');
      expect(back.queryParameters['code'], 'one-time-code');
      expect(back.queryParameters['link'], 'link1');
      expect(back.queryParameters.containsKey('slug'), isFalse);
      expect(find.textContaining('has the link'), findsOneWidget);

      // Connecting on its own: consent, then back with the one-time code.
      authorized.clear();
      launched.clear();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(Brightness.light),
          home: ConnectScreen(
            request: ConnectRequest(
              client: tool,
              name: 'Mietunterlagen',
              redirect: '$tool/',
              state: 'st-2',
              challenge: 'd' * 43,
              reasons: const ToolReasons(revoke: 'To end a link you remove'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Mietunterlagen wants to connect'), findsOneWidget);
      expect(find.textContaining('Read your vault'), findsOneWidget);
      // The tool's reason is quoted as its own words; unticking is respected.
      expect(
        find.text('Mietunterlagen says: “To end a link you remove”'),
        findsOneWidget,
      );
      // The decision is pinned to the bottom, so a choice further down the
      // page has to be scrolled into view before it can be tapped.
      await tester.ensureVisible(find.text('Receive the links it proposed'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Receive the links it proposed'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      expect(authorized.single['challenge'], 'd' * 43);
      expect(authorized.single['allowRevoke'], true);
      expect(authorized.single['allowHandOver'], false);
      final connected = Uri.parse(launched.single);
      expect(connected.queryParameters['status'], 'connected');
      expect(connected.queryParameters['code'], 'one-time-code');
      expect(connected.queryParameters['state'], 'st-2');
      expect(find.text('Mietunterlagen is connected'), findsOneWidget);

      // A page that watches this server collects its answer itself: nothing
      // is opened, and the owner compares the code the page shows.
      authorized.clear();
      launched.clear();
      final watched = ToolClient.origin(Stores.api.baseUrl)!;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(Brightness.light),
          home: ConnectScreen(
            request: ConnectRequest(
              client: tool,
              name: 'Mietunterlagen',
              redirect: '$tool/',
              state: 'st-3',
              challenge: 'E9LVI17tLpGpM3ZvzAq5HMYjQ3Z4Q1F2U6JtVZ0QxkA',
              poll: watched,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('83C-047'), findsOneWidget);
      await tester.ensureVisible(find.text('Connect'));
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      expect(authorized.single['poll'], true);
      expect(authorized.single.containsKey('reuse'), isFalse);
      expect(launched, isEmpty);
      expect(find.textContaining('carries on by itself'), findsOneWidget);
      expect(find.text('Back to Mietunterlagen'), findsNothing);
    },
  );
}
