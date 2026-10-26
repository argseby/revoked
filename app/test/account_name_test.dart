import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobx/mobx.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:revoked_app/core/models/sign_in_request.dart';
import 'package:revoked_app/core/models/user.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/theme/app_theme.dart';
import 'package:revoked_app/core/widgets/app_checkbox.dart';
import 'package:revoked_app/features/connections/view/sign_in_approval_screen.dart';

/// "Your name" at a sign-in used to be a checkbox even when the account had
/// no name, and nothing anywhere could set one. Now the name is the
/// account's own, set from Settings or right where it is asked for.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  var preview = '';
  final patches = <Map<String, dynamic>>[];

  Future<http.Response> server(http.Request request) async {
    http.Response json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    );
    final path = request.url.path;
    if (path == '/oidc/authorize/app') {
      return json({
        'ticket': 'tkt0123456789',
        'client': 'https://game.example',
        'account': {'email': 'ada@home.test'},
        'scopes': [
          {'scope': 'profile', 'value': preview},
          {'scope': 'email', 'value': 'ada@home.test'},
        ],
        'links': <Object>[],
      });
    }
    if (path == '/api/collections/users/records/u1' &&
        request.method == 'PATCH') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      patches.add(body);
      return json({'id': 'u1', 'email': 'ada@home.test', ...body});
    }
    return json({'items': <Object>[]});
  }

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await Stores.init(httpClient: MockClient(server));
  });

  setUp(() {
    patches.clear();
    runInAction(
      () => Stores.auth.currentUser = User.fromJson({
        'id': 'u1',
        'email': 'ada@home.test',
        'name': preview,
      }),
    );
  });

  test('the account name is read, and missing means empty', () {
    expect(User.fromJson({'id': 'u', 'name': 'Ada'}).name, 'Ada');
    expect(User.fromJson({'id': 'u'}).name, '');
  });

  final request = SignInRequest.fromQuery({
    'client_id': 'https://game.example',
    'redirect_uri': 'https://game.example/callback',
    'response_type': 'code',
    'scope': 'openid profile email',
    'state': 'st-1',
    'nonce': 'n-1',
    'code_challenge': 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
    'code_challenge_method': 'S256',
  })!;

  Future<void> show(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.light),
        home: SignInApprovalScreen(request: request),
      ),
    );
    await tester.pumpAndSettle();
  }

  AppCheckRow? nameRow(WidgetTester tester) {
    final rows = tester
        .widgetList<AppCheckRow>(find.byType(AppCheckRow))
        .where((r) => r.label == 'Your name');
    return rows.isEmpty ? null : rows.single;
  }

  testWidgets('no name yet: an Add button, not a checkbox', (tester) async {
    preview = '';
    await show(tester);
    expect(nameRow(tester), isNull);
    expect(find.textContaining('No name yet'), findsOneWidget);

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Ada Lovelace');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(patches.single, {'name': 'Ada Lovelace'});
    expect(Stores.auth.currentUser!.name, 'Ada Lovelace');
    // Added here to be shared: shown, and ticked.
    expect(nameRow(tester)!.subtitle, 'Ada Lovelace');
    expect(nameRow(tester)!.value, isTrue);
  });

  testWidgets('a name can be changed where it is asked for', (tester) async {
    preview = 'Ada';
    runInAction(
      () => Stores.auth.currentUser = User.fromJson({
        'id': 'u1',
        'email': 'ada@home.test',
        'name': 'Ada',
      }),
    );
    await show(tester);
    expect(nameRow(tester)!.subtitle, 'Ada');

    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Ada King');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(patches.single, {'name': 'Ada King'});
    expect(nameRow(tester)!.subtitle, 'Ada King');
  });

  testWidgets('emptying the field here removes nothing', (tester) async {
    preview = 'Ada';
    runInAction(
      () => Stores.auth.currentUser = User.fromJson({
        'id': 'u1',
        'email': 'ada@home.test',
        'name': 'Ada',
      }),
    );
    await show(tester);
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(patches, isEmpty);
    expect(nameRow(tester)!.subtitle, 'Ada');
  });
}
