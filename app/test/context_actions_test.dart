import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobx/mobx.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:revoked_app/core/models/link.dart';
import 'package:revoked_app/core/models/record.dart' as models;
import 'package:revoked_app/core/models/request.dart';
import 'package:revoked_app/core/models/user.dart';
import 'package:revoked_app/core/models/workspace_member.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/theme/app_theme.dart';
import 'package:revoked_app/core/widgets/app_list_row.dart';
import 'package:revoked_app/core/widgets/app_options_sheet.dart';
import 'package:revoked_app/features/requests/view/request_actions.dart';
import 'package:revoked_app/features/requests/view/inbox_screen.dart';
import 'package:revoked_app/features/sealing/store/keys_store.dart';
import 'package:revoked_app/features/shares/view/share_actions.dart';
import 'package:revoked_app/features/vault/view/record_actions.dart';

void main() {
  late BuildContext context;
  late models.Record record;
  var mayEdit = false;
  String? copied;
  final deleted = <String>[];
  final accessChecks = <String>[];

  setUp(() async {
    mayEdit = false;
    copied = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          if (call.method == 'Clipboard.getData') return {'text': copied};
          return null;
        });
    deleted.clear();
    accessChecks.clear();
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await Stores.init(
      httpClient: MockClient((request) async {
        if (request.method == 'DELETE') {
          deleted.add(request.url.path);
          return http.Response('', 204);
        }
        if (request.url.path.startsWith('/api/access/')) {
          accessChecks.add(request.url.path);
          return http.Response(jsonEncode({'canEdit': mayEdit}), 200);
        }
        return http.Response('{"items":[]}', 200);
      }),
    );
    record = models.Record(
      id: 'r1',
      key: 'email',
      value: 'ada@example.com',
      label: 'Email',
      type: 'text',
      format: 'default',
      user: 'me',
      workspace: 'w1',
    );
    runInAction(() {
      Stores.auth.currentUser = User.fromJson({
        'id': 'me',
        'email': 'me@example.com',
        'activeWorkspace': 'w1',
      });
      Stores.settings.memberships.add(
        WorkspaceMember(id: 'm1', user: 'me', workspace: 'w1', role: 'admin'),
      );
      Stores.keys.status = SealingStatus.notSetUp;
      Stores.vault.records.add(record);
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (ctx) {
              context = ctx;
              return AppListRow(
                icon: Icons.description,
                title: record.label,
                onTap: () {},
                contextActions: () => RecordActions(ctx).forRecord(record),
              );
            },
          ),
        ),
      ),
    );
  }

  List<String> labels(List<AppSheetAction> actions) =>
      actions.map((a) => a.label).toList();
  Link link({String user = 'me', String status = 'active'}) => Link(
    id: 'l1',
    slug: 'slug',
    label: 'Accountant',
    sections: [],
    records: [],
    user: user,
    workspace: 'w1',
    status: status,
  );
  DataRequest request({String user = 'me'}) => DataRequest.fromJson({
    'id': 'q1',
    'user': user,
    'workspace': 'w1',
    'label': 'Onboarding',
    'status': 'active',
  });

  testWidgets('own record exposes the same seven detail actions', (
    tester,
  ) async {
    await pump(tester);
    expect(labels(RecordActions(context).forRecord(record)), [
      'Copy value',
      'Share',
      'Visibility',
      'Edit',
      'Encrypt end to end',
      'Duplicate',
      'Delete',
    ]);
    await tester.longPress(find.text('Email'));
    await tester.pumpAndSettle();
    expect(find.text('Copy value'), findsOneWidget);
    await tester.tap(find.text('Copy value'));
    await tester.pumpAndSettle();
    expect(copied, 'ada@example.com');
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets(
    'locked record cannot copy, share, edit, duplicate or change encryption',
    (tester) async {
      record = models.Record(
        id: 'locked',
        key: 'secret',
        label: 'Secret',
        value: '',
        type: 'text',
        format: 'default',
        user: 'me',
        workspace: 'w1',
        sealed: true,
      );
      await pump(tester);
      expect(labels(RecordActions(context).forRecord(record)), [
        'Visibility',
        'Delete',
      ]);
    },
  );

  testWidgets(
    'context deletion confirms, supports cancellation and keeps the list route',
    (tester) async {
      await pump(tester);
      Future<void> openDelete() async {
        await tester.longPress(find.text('Email'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();
      }

      await openDelete();
      expect(deleted, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(deleted, isEmpty);
      await openDelete();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(deleted, ['/api/collections/records/records/r1']);
      expect(find.byType(AppListRow), findsOneWidget);
      expect(Stores.vault.records, isEmpty);
    },
  );

  testWidgets('revoked links cannot be activated from contextual options', (
    tester,
  ) async {
    await pump(tester);
    expect(
      labels(
        ShareActions(context).forShare(link(status: 'revoked'), editable: true),
      ),
      ['Visibility', 'Edit', 'Duplicate', 'Delete'],
    );
  });

  testWidgets('shared link permissions are checked on every invocation', (
    tester,
  ) async {
    await pump(tester);
    final colleague = link(user: 'colleague');
    final readOnly = labels(await shareContextActions(context, colleague));
    expect(readOnly, ['Share link', 'View as recipient']);
    mayEdit = true;
    final editable = labels(await shareContextActions(context, colleague));
    expect(editable, containsAll(['Edit', 'Pause', 'Revoke', 'Delete']));
    expect(editable, isNot(contains('Visibility')));
    expect(editable, isNot(contains('Duplicate')));
    expect(accessChecks.length, 2);
  });

  testWidgets(
    'read-only requests offer views and sharing; editors cannot change visibility',
    (tester) async {
      await pump(tester);
      final colleague = request(user: 'colleague');
      expect(labels(await requestContextActions(context, colleague)), [
        'View responses',
        'View as sheet',
        'Share',
      ]);
      mayEdit = true;
      final editable = labels(await requestContextActions(context, colleague));
      expect(editable, containsAll(['Edit', 'Revoke', 'Delete']));
      expect(editable, isNot(contains('Visibility')));
    },
  );
  testWidgets('request list exposes detail actions on long press', (
    tester,
  ) async {
    runInAction(() {
      Stores.requests.requests.add(request());
      Stores.requests.loadState.succeed(Stores.requests.loadState.begin());
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.light),
        home: const Scaffold(body: InboxScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Onboarding'));
    await tester.longPress(find.text('Onboarding'));
    await tester.pumpAndSettle();
    for (final label in [
      'View responses',
      'View as sheet',
      'Share',
      'Visibility',
      'Edit',
      'Revoke',
      'Delete',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
}
