import 'package:flutter/material.dart';
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
}) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  await Stores.init(
    httpClient: MockClient((_) async => http.Response('{"items":[]}', 200)),
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
  testWidgets('sharing overview previews contents and filters link states', (
    tester,
  ) async {
    await _show(tester);
    expect(find.text('Your sharing'), findsOneWidget);
    expect(find.text('Share items'), findsOneWidget);
    expect(find.text('Email address'), findsNWidgets(3));
    expect(find.textContaining('secret-email@example.com'), findsNothing);
    expect(find.text('Landlord'), findsOneWidget);
    expect(find.text('Employer HR'), findsOneWidget);
    expect(find.text('Insurance'), findsOneWidget);
    expect(find.text('Bank'), findsNothing);

    await tester.tap(find.text('Closed links'));
    await tester.pumpAndSettle();
    expect(find.text('Bank'), findsOneWidget);
    expect(find.text('Landlord'), findsNothing);

    await tester.tap(find.text('Active links'));
    await tester.pumpAndSettle();
    expect(find.text('Landlord'), findsOneWidget);
    expect(find.text('Employer HR'), findsOneWidget);
    expect(find.text('Insurance'), findsNothing);
    expect(find.text('Bank'), findsNothing);

    await tester.enterText(find.byType(TextFormField), 'land');
    await tester.pumpAndSettle();
    expect(find.text('Landlord'), findsOneWidget);
    expect(find.text('Employer HR'), findsNothing);
  });

  for (final brightness in Brightness.values) {
    for (final width in [320.0, 600.0, 1400.0]) {
      testWidgets(
        'populated shares fit $width in ${brightness.name} at 200% text',
        (tester) async {
          await _show(tester, width: width, brightness: brightness, scale: 2);
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.text('Paused links'));
          await tester.tap(find.text('Paused links'));
          await tester.pumpAndSettle();
          expect(find.text('Insurance'), findsOneWidget);
          expect(find.text('Landlord'), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
