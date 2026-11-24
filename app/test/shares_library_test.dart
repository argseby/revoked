import 'package:material_ui/material_ui.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobx/mobx.dart';
import 'package:revoked_app/core/design/app_icons.dart';
import 'package:revoked_app/core/models/link.dart';
import 'package:revoked_app/core/models/record.dart' as models;
import 'package:revoked_app/core/models/user.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/theme/app_theme.dart';
import 'package:revoked_app/features/shares/view/shares_screen.dart';
import 'package:revoked_app/features/shares/view/share_detail_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _show(
  WidgetTester tester, {
  double width = 1400,
  Brightness brightness = Brightness.light,
  double scale = 1,
  http.Client? client,
  Widget page = const SharesScreen(),
}) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  await Stores.init(
    httpClient:
        client ?? MockClient((_) async => http.Response('{"items":[]}', 200)),
  );
  runInAction(() {
    Stores.auth.currentUser = User.fromJson({
      'id': 'u',
      'email': 'jamie@example.com',
      'activeWorkspace': 'w',
    });
    Stores.shares.shares.addAll([
      for (final (id, name, status, expires) in [
        ('lease', 'Landlord', 'active', null),
        (
          'hr',
          'Employer HR',
          'active',
          DateTime.now().add(const Duration(days: 2)).toIso8601String(),
        ),
        ('insurance', 'Insurance', 'paused', null),
        ('bank', 'Bank', 'revoked', null),
      ])
        Link(
          id: id,
          slug: id,
          label: name,
          status: status,
          expiresAt: expires,
          sections: [],
          records: ['email'],
          user: 'u',
          workspace: 'w',
        ),
    ]);
    Stores.vault.records.add(
      models.Record(
        id: 'email',
        key: 'email',
        value: 'secret-email@example.com',
        label: 'Email address',
        type: 'text',
        format: 'default',
        user: 'u',
        workspace: 'w',
      ),
    );
    Stores.shares.loadState.succeed(Stores.shares.loadState.begin());
    Stores.vault.loadState.succeed(Stores.vault.loadState.begin());
  });
  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(brightness),
      home: Scaffold(body: page),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('access comes before Copy link and named secondary actions', (
    tester,
  ) async {
    String? copied;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map<Object?, Object?>)['text'] as String;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await _show(
      tester,
      width: 400,
      page: const ShareDetailScreen(shareId: 'lease'),
    );

    final copy = find.text('Copy link');
    for (final fact in [
      find.textContaining('Anyone with this link'),
      find.text('Contents · 1 record').first,
      find.text('No expiry'),
    ]) {
      expect(
        tester.getBottomLeft(fact).dy,
        lessThan(tester.getTopLeft(copy).dy),
      );
    }
    await tester.tap(copy);
    await tester.pumpAndSettle();
    expect(copied, '${Stores.api.baseUrl}/s/lease');

    expect(find.text('Visibility'), findsNothing);
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(find.text('Visibility'), findsOneWidget);
    expect(find.text('Share options'), findsOneWidget);
    expect(find.text('View as recipient'), findsOneWidget);
  });

  testWidgets('an unavailable encryption key is explained before copying', (
    tester,
  ) async {
    bool copied = false;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = true;
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await _show(tester, page: const ShareDetailScreen(shareId: 'encrypted'));
    runInAction(
      () => Stores.shares.shares.add(
        Link(
          id: 'encrypted',
          slug: 'encrypted',
          label: 'Encrypted share',
          user: 'u',
          workspace: 'w',
          records: const ['email'],
          sections: const [],
          status: 'active',
          sealedKeyWraps: const {'unknown-device': 'unreadable'},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy link'));
    await tester.pumpAndSettle();

    expect(copied, isFalse);
    expect(
      find.textContaining(
        'The key of this link is not readable on this device',
      ),
      findsOneWidget,
    );
  });

  testWidgets('sharing rows expose their detail actions on long press', (
    tester,
  ) async {
    await _show(tester, width: 400);
    await tester.ensureVisible(find.text('Landlord'));
    await tester.longPress(find.text('Landlord'));
    await tester.pumpAndSettle();
    expect(find.text('Share link'), findsOneWidget);
    expect(find.text('Visibility'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Duplicate'), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('Revoke'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sharing overview previews contents and filters link states', (
    tester,
  ) async {
    await _show(tester);
    expect(
      tester.getTopLeft(find.text('Active 2')).dy,
      greaterThan(tester.getBottomLeft(find.byType(TextFormField)).dy),
    );
    expect(find.text('Your sharing'), findsOneWidget);
    expect(find.text('New link'), findsOneWidget);
    expect(find.text('Email address'), findsNWidgets(3));
    expect(find.textContaining('secret-email@example.com'), findsNothing);
    expect(find.text('Landlord'), findsOneWidget);
    expect(find.text('Employer HR'), findsOneWidget);
    expect(find.text('Insurance'), findsOneWidget);
    expect(find.text('Bank'), findsNothing);

    await tester.tap(find.text('Revoked or expired 1'));
    await tester.pumpAndSettle();
    expect(find.text('Status: Revoked or expired'), findsOneWidget);
    expect(find.text('Bank'), findsOneWidget);
    expect(find.text('Landlord'), findsNothing);

    await tester.tap(find.text('Active 2'));
    await tester.pumpAndSettle();
    expect(find.text('Status: Active'), findsOneWidget);
    expect(find.text('Status: Needs attention'), findsNothing);
    expect(find.text('Landlord'), findsOneWidget);
    expect(find.text('Employer HR'), findsOneWidget);
    expect(find.text('Insurance'), findsNothing);
    expect(find.text('Bank'), findsNothing);

    await tester.enterText(find.byType(TextFormField), 'land');
    await tester.pumpAndSettle();
    expect(find.text('Landlord'), findsOneWidget);
    expect(find.text('Employer HR'), findsNothing);
  });

  testWidgets('share arrows align and active status fits in an icon', (
    tester,
  ) async {
    await _show(tester);
    runInAction(
      () => Stores.shares.shares.add(
        Link(
          id: 'empty',
          slug: 'empty',
          label: 'No records',
          records: const [],
          sections: const [],
          status: 'active',
          user: 'u',
          workspace: 'w',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final expandable = find.byKey(const ValueKey('link-lease'));
    final plain = find.byKey(const ValueKey('link-empty'));
    final openArrow = find.descendant(
      of: plain,
      matching: find.byIcon(AppIcons.chevronRight),
    );
    final expandArrow = find.descendant(
      of: expandable,
      matching: find.byIcon(AppIcons.chevronDown),
    );
    expect(tester.getCenter(openArrow).dx, tester.getCenter(expandArrow).dx);

    final active = find.descendant(
      of: expandable,
      matching: find.byTooltip('Active'),
    );
    expect(tester.getSize(active).width, 16);
    expect(tester.widget<Text>(find.text('Landlord')).maxLines, 2);
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: expandable,
              matching: find.text('Email address'),
            ),
          )
          .maxLines,
      1,
    );
    expect(
      find.descendant(of: expandable, matching: find.text('Active')),
      findsNothing,
    );
  });

  testWidgets('the attention filter and per-record access open from Shares', (
    tester,
  ) async {
    await _show(tester);
    await tester.tap(find.text('Needs attention 1'));
    await tester.pumpAndSettle();
    expect(find.text('Employer HR'), findsOneWidget);
    expect(find.text('Landlord'), findsNothing);

    await tester.ensureVisible(find.text('Access by record'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Access by record'));
    await tester.pumpAndSettle();
    expect(find.text('Shared with others'), findsOneWidget);
    expect(find.text('2 links'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('live links group by creator and open to what they expose', (
    tester,
  ) async {
    await _show(tester);
    runInAction(
      () => Stores.shares.shares.addAll([
        Link(
          id: 'answer',
          slug: 'answer',
          label: 'Onboarding answer',
          status: 'active',
          sections: [],
          records: ['email'],
          user: 'u',
          workspace: 'w',
          request: 'request00000001',
        ),
        Link(
          id: 'tool',
          slug: 'tool',
          label: 'Flat 3B',
          status: 'active',
          sections: [],
          records: ['gone'],
          user: 'u',
          workspace: 'w',
          proposedBy: 'https://homes.example',
        ),
      ]),
    );
    await tester.pumpAndSettle();
    double top(String key) => tester.getRect(find.byKey(ValueKey(key))).top;
    // Own, then the tool, then answers; what needs a look stays above.
    expect(top('link-hr'), lessThan(top('links-by-own')));
    expect(top('links-by-own'), lessThan(top('links-by-tool:homes.example')));
    expect(
      top('links-by-tool:homes.example'),
      lessThan(top('links-by-answers')),
    );
    expect(find.text('homes.example'), findsOneWidget);
    expect(find.text('Answers to requests'), findsOneWidget);

    expect(find.byKey(const ValueKey('link-record-gone')), findsNothing);
    final expand = find.descendant(
      of: find.byKey(const ValueKey('link-tool')),
      matching: find.byTooltip('Expand'),
    );
    await tester.tap(expand);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('link-record-gone')), findsOneWidget);
    expect(find.text('No longer in the vault'), findsOneWidget);
    expect(find.text('Single record'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an opened link stays open when the list is opened again', (
    tester,
  ) async {
    await _show(tester);
    final contents = find.byKey(const ValueKey('link-record-email'));
    expect(contents, findsNothing);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('link-lease')),
        matching: find.byTooltip('Expand'),
      ),
    );
    await tester.pumpAndSettle();
    expect(contents, findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.light),
        home: const Scaffold(body: SharesScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(contents, findsOneWidget);
  });

  testWidgets('revoked group expands and folds back even when filtered', (
    tester,
  ) async {
    await _show(tester);
    await tester.tap(find.text('Revoked or expired 1'));
    await tester.pumpAndSettle();
    expect(find.text('Bank'), findsOneWidget);
    await tester.ensureVisible(find.text('Hide 1 link'));
    await tester.tap(find.text('Hide 1 link'));
    await tester.pumpAndSettle();
    expect(find.text('Bank'), findsNothing);
    await tester.tap(find.text('Show 1 link'));
    await tester.pumpAndSettle();
    expect(find.text('Bank'), findsOneWidget);
  });

  testWidgets('bulk delete confirms and removes only matching terminal links', (
    tester,
  ) async {
    final deleted = <String>[];
    await _show(
      tester,
      client: MockClient((request) async {
        if (request.method == 'DELETE') {
          deleted.add(request.url.path.split('/').last);
        }
        return http.Response('{"items":[]}', 200);
      }),
    );
    runInAction(
      () => Stores.shares.shares.add(
        Link(
          id: 'expired',
          slug: 'expired',
          label: 'Old contract',
          status: 'expired',
          sections: [],
          records: [],
          user: 'u',
          workspace: 'w',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'bank');
    await tester.pumpAndSettle();
    final remove = find.byTooltip('Delete all revoked or expired links shown');
    await tester.ensureVisible(remove);
    await tester.tap(remove);
    await tester.pumpAndSettle();
    expect(deleted, isEmpty);
    expect(find.text('Delete 1 link?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(deleted, isEmpty);
    await tester.tap(remove);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete link'));
    await tester.pumpAndSettle();
    expect(deleted, ['bank']);
    expect(
      Stores.shares.shares.map((link) => link.id),
      containsAll(['lease', 'hr', 'insurance', 'expired']),
    );
  });

  testWidgets(
    'bulk deletion reports partial failures and retains failed links',
    (tester) async {
      final deleted = <String>[];
      await _show(
        tester,
        client: MockClient((request) async {
          if (request.method == 'DELETE') {
            final id = request.url.path.split('/').last;
            deleted.add(id);
            return http.Response('{}', id == 'bank' ? 403 : 204);
          }
          return http.Response('{"items":[]}', 200);
        }),
      );
      runInAction(
        () => Stores.shares.shares.add(
          Link(
            id: 'expired',
            slug: 'expired',
            label: 'Old contract',
            status: 'expired',
            sections: [],
            records: [],
            user: 'u',
            workspace: 'w',
          ),
        ),
      );
      await tester.pumpAndSettle();
      final remove = find.byTooltip(
        'Delete all revoked or expired links shown',
      );
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete 2 links'));
      await tester.pumpAndSettle();
      expect(deleted, containsAll(['bank', 'expired']));
      expect(
        Stores.shares.shares.map((link) => link.id),
        containsAll(['lease', 'hr', 'insurance', 'bank']),
      );
      expect(Stores.shares.shares.any((link) => link.id == 'expired'), isFalse);
      expect(find.text('1 deleted · 1 could not be deleted'), findsOneWidget);
    },
  );

  for (final brightness in Brightness.values) {
    for (final width in [320.0, 600.0, 1400.0]) {
      testWidgets(
        'populated shares fit $width in ${brightness.name} at 200% text',
        (tester) async {
          await _show(tester, width: width, brightness: brightness, scale: 2);
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.text('Paused 1'));
          await tester.tap(find.text('Paused 1'));
          await tester.pumpAndSettle();
          expect(find.text('Insurance'), findsOneWidget);
          expect(find.text('Landlord'), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
