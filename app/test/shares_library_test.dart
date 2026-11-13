import 'package:material_ui/material_ui.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobx/mobx.dart';
import 'package:revoked_app/core/models/link.dart';
import 'package:revoked_app/core/models/record.dart' as models;
import 'package:revoked_app/core/models/user.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/theme/app_theme.dart';
import 'package:revoked_app/features/shares/view/shares_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _show(
  WidgetTester tester, {
  double width = 1400,
  Brightness brightness = Brightness.light,
  double scale = 1,
  http.Client? client,
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
      home: const Scaffold(body: SharesScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
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
