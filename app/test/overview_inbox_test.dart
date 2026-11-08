import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/models/api_key.dart';
import 'package:revoked_app/core/models/link.dart';
import 'package:revoked_app/core/models/notification.dart';
import 'package:revoked_app/core/models/record.dart' as models;
import 'package:revoked_app/core/models/request.dart';
import 'package:revoked_app/core/models/webhook.dart';
import 'package:revoked_app/core/router/app_router.dart';
import 'package:revoked_app/features/overview/inbox.dart';
import 'package:revoked_app/features/overview/view/overview_screen.dart';

final now = DateTime(2026, 11, 8, 12);

String iso(DateTime t) => t.toUtc().toIso8601String();

Link link(
  String id, {
  String label = '',
  String status = 'active',
  DateTime? expires,
  int maxViews = 0,
  int viewCount = 0,
  List<String> records = const [],
  DateTime? created,
  DateTime? updated,
}) => Link(
  id: id,
  slug: id,
  label: label,
  sections: const [],
  records: records,
  user: 'u',
  workspace: 'w',
  status: status,
  expiresAt: expires == null ? null : iso(expires),
  maxViews: maxViews,
  viewCount: viewCount,
  created: created == null ? null : iso(created),
  updated: updated == null ? null : iso(updated),
);

AppNotification answer(
  String id,
  String requestId, {
  bool read = false,
  DateTime? at,
}) => AppNotification(
  id: id,
  user: 'u',
  workspace: 'w',
  type: requestResponseType,
  title: 'New response',
  refId: requestId,
  read: read,
  created: at == null ? null : iso(at),
);

DataRequest request(String id, String label) => DataRequest(
  id: id,
  slug: id,
  label: label,
  status: 'active',
  identity: '',
  user: 'u',
  workspace: 'w',
);

WebhookEndpoint webhook(String id, {bool failing = false}) => WebhookEndpoint(
  id: id,
  url: 'https://hooks.example.com/in',
  description: '',
  events: const ['*'],
  enabled: true,
  disabledReason: '',
  failingSince: failing ? now : null,
  created: null,
  succeeded: 0,
  failed: 0,
  pending: 0,
);

ApiKey apiKey(String id, String label, {DateTime? expires}) => ApiKey(
  id: id,
  label: label,
  token: '',
  user: 'u',
  workspace: 'w',
  scopes: const [],
  expiresAt: expires == null ? null : iso(expires),
);

models.Record record(
  String id,
  String label, {
  required DateTime created,
  DateTime? updated,
}) => models.Record(
  id: id,
  key: id,
  value: 'v',
  label: label,
  type: 'text',
  format: 'default',
  user: 'u',
  workspace: 'w',
  created: iso(created),
  updated: iso(updated ?? created),
);

List<NeedItem> needs({
  List<Link> links = const [],
  List<AppNotification> notifications = const [],
  List<DataRequest> requests = const [],
  List<WebhookEndpoint> webhooks = const [],
  List<ApiKey> keys = const [],
  bool showAnswers = true,
}) => needsYouItems(
  links: links,
  notifications: notifications,
  requests: requests,
  webhooks: webhooks,
  apiKeys: keys,
  now: now,
  showAnswers: showAnswers,
);

void main() {
  group('needsYouItems', () {
    test('nothing pending gives no rows', () {
      expect(needs(links: [link('a', label: 'Wi-Fi')]), isEmpty);
    });

    test('unread answers are counted per request and named', () {
      final items = needs(
        notifications: [
          answer('1', 'r1'),
          answer('2', 'r1'),
          answer('3', 'r2'),
          answer('4', 'r2', read: true),
        ],
        requests: [request('r1', 'Payroll')],
      );
      expect(items.map((i) => i.text), [
        '2 new answers to Payroll',
        '1 new answer to a request',
      ]);
      expect(items.first.route, AppRoutes.requestDetailFor('r1'));
      expect(items.first.tone, NeedTone.info);
    });

    test('answers are left out when requests are hidden', () {
      expect(
        needs(notifications: [answer('1', 'r1')], showAnswers: false),
        isEmpty,
      );
    });

    test('one row per ending link, soonest first', () {
      final items = needs(
        links: [
          link(
            'later',
            label: 'Lease',
            expires: now.add(const Duration(days: 2, hours: 1)),
          ),
          link('soon', label: 'Wi-Fi', expires: DateTime(2026, 11, 9, 10)),
          link('views', label: 'Doctor', maxViews: 5, viewCount: 4),
        ],
      );
      expect(items.map((i) => i.text), [
        'Wi-Fi link ends tomorrow',
        'Lease link ends in 2 days',
        'Doctor link has 1 view left',
      ]);
      expect(items.first.route, AppRoutes.shareDetailFor('soon'));
    });

    test('failing webhooks, expiring keys and paused links each get a row', () {
      final items = needs(
        links: [link('p', label: 'Gym', status: 'paused')],
        webhooks: [webhook('w1', failing: true), webhook('w2')],
        keys: [
          apiKey('k1', 'CI', expires: now.add(const Duration(days: 3))),
          apiKey('k2', 'Old', expires: now.add(const Duration(days: 30))),
        ],
      );
      expect(items.map((i) => i.text), [
        'Webhook failing: hooks.example.com',
        'API key CI expires in 3 days',
        'Gym link is paused',
      ]);
      expect(items.map((i) => i.route), [
        AppRoutes.webhookFor('w1'),
        AppRoutes.apiKeys,
        AppRoutes.shareDetailFor('p'),
      ]);
    });
  });

  group('recentItems', () {
    test('mixes records, links and answers newest first', () {
      final items = recentItems(
        records: [
          record(
            'addr',
            'Address',
            created: now.subtract(const Duration(days: 9)),
            updated: now.subtract(const Duration(hours: 1)),
          ),
          record(
            'iban',
            'IBAN',
            created: now.subtract(const Duration(days: 3)),
          ),
        ],
        sections: const [],
        links: [
          link(
            'l1',
            label: 'Landlord',
            records: ['addr'],
            created: now.subtract(const Duration(hours: 2)),
          ),
          link(
            'l2',
            label: 'Bank',
            records: ['addr'],
            created: now.subtract(const Duration(days: 20)),
          ),
        ],
        notifications: [
          answer('n1', 'r1', at: now.subtract(const Duration(minutes: 5))),
        ],
        requests: [request('r1', 'Payroll')],
        limit: 4,
      );
      expect(items.map((i) => '${i.title} · ${i.subtitle}'), [
        'Payroll · new answer',
        'Address · edited · reaches 2 people',
        'Landlord · Link · shared · 1 record',
        'IBAN · added · not shared',
      ]);
    });
  });

  testWidgets('a need row shows its line and opens on tap', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NeedRow(
            item: const NeedItem(
              icon: AppIcons.clock,
              text: 'Wi-Fi link ends tomorrow',
              route: '/shared/a',
            ),
            onTap: () => tapped++,
          ),
        ),
      ),
    );
    expect(find.text('Wi-Fi link ends tomorrow'), findsOneWidget);
    await tester.tap(find.text('Wi-Fi link ends tomorrow'));
    expect(tapped, 1);
  });
}
