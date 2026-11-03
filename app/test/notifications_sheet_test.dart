import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:revoked_app/core/models/notification.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/features/notifications/view/notifications_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 11, 3, 15);

  Map<String, dynamic> json(String id, DateTime created, {bool read = false}) =>
      {
        'id': id,
        'user': 'u1',
        'workspace': 'w1',
        'type': 'request_response',
        'title': 'Notification $id',
        'message': 'Someone answered your request.',
        'read': read,
        'created': created.toUtc().toIso8601String(),
      };

  group('notificationTimeAgo', () {
    test('reads like a person would say it', () {
      expect(notificationTimeAgo(now, now), 'Just now');
      expect(
        notificationTimeAgo(now.subtract(const Duration(minutes: 5)), now),
        '5 min ago',
      );
      expect(
        notificationTimeAgo(now.subtract(const Duration(hours: 3)), now),
        '3 h ago',
      );
      expect(notificationTimeAgo(DateTime(2026, 11, 2, 23), now), 'Yesterday');
      expect(notificationTimeAgo(DateTime(2026, 10, 30), now), 'Fri');
      expect(notificationTimeAgo(DateTime(2026, 10, 12), now), '12 Oct');
      expect(notificationTimeAgo(DateTime(2025, 10, 12), now), '12 Oct 2025');
    });
  });

  test('groups by day and drops the empty groups', () {
    final items = [
      AppNotification.fromJson(json('a', now)),
      AppNotification.fromJson(json('b', DateTime(2026, 11, 2, 9))),
      AppNotification.fromJson(json('c', DateTime(2026, 9, 1))),
    ];
    final groups = groupNotificationsByDay(items, now);
    expect(groups.map((g) => g.$1), ['Today', 'Yesterday', 'Earlier']);
    expect(groups.map((g) => g.$2.single.id), ['a', 'b', 'c']);
  });

  group('the sheet', () {
    late List<String> deleted;

    Future<void> open(WidgetTester tester, Size size, int count) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      deleted = [];
      final created = DateTime.now();
      final items = [
        for (var i = 0; i < count; i++)
          json('n$i', created.subtract(Duration(hours: i * 7)), read: i.isOdd),
      ];
      await Stores.init(
        httpClient: MockClient((req) async {
          if (req.method == 'DELETE') {
            deleted.add(req.url.pathSegments.last);
            return http.Response('', 204);
          }
          if (req.url.path.endsWith('/notifications/records')) {
            return http.Response(jsonEncode({'items': items}), 200);
          }
          return http.Response('{}', 404);
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => openNotificationsSheet(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    const sizes = {
      'small phone': Size(320, 640),
      'phone': Size(375, 812),
      'phone on its side': Size(812, 375),
      'tablet': Size(768, 1024),
      'desktop': Size(1280, 800),
    };

    for (final MapEntry(key: name, value: size) in sizes.entries) {
      testWidgets('fits a $name', (tester) async {
        await open(tester, size, 20);
        expect(tester.takeException(), isNull);
        expect(find.text('Notification n0'), findsOneWidget);
      });
    }

    testWidgets('fills the side panel instead of stopping at 70%', (
      tester,
    ) async {
      await open(tester, sizes['desktop']!, 20);
      final list = tester.getRect(find.byType(ListView));
      expect(list.bottom, greaterThan(sizes['desktop']!.height * 0.9));
    });

    testWidgets('deletes one notification from its menu', (tester) async {
      await open(tester, sizes['desktop']!, 3);
      await tester.tap(find.byTooltip('Options').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      expect(deleted, ['n0']);
      expect(find.text('Notification n0'), findsNothing);
    });

    testWidgets('deletes one with a swipe', (tester) async {
      await open(tester, sizes['phone']!, 3);
      await tester.drag(find.text('Notification n0'), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(deleted, ['n0']);
      expect(find.text('Notification n0'), findsNothing);
    });

    testWidgets('deletes every read one and keeps the unread', (tester) async {
      await open(tester, sizes['desktop']!, 4);
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete 2 read notifications'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      expect(deleted, unorderedEquals(['n1', 'n3']));
      expect(find.text('Notification n0'), findsOneWidget);
      expect(find.text('Notification n2'), findsOneWidget);
    });
  });
}
