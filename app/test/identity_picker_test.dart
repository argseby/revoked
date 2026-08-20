import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revoked_app/core/models/identity.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/identity_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Choosing which key signs a response is a required step on the public
/// request screen — if the rows do not respond to a tap, the request cannot
/// be answered at all.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Identity id(String name, {String domain = 'example.com'}) => Identity(
    id: name,
    name: name,
    certificate: 'cert',
    fingerprint: 'f' * 64,
    user: 'u',
    workspace: 'w',
    domainAtIssue: domain,
  );

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Stores.init();
  });

  setUp(() {
    Stores.identities.identities
      ..clear()
      ..addAll([id('alpha'), id('beta', domain: 'other.example')]);
  });

  testWidgets('tapping a row reports the chosen identity', (tester) async {
    String? chosen;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IdentityPicker(selectedId: null, onChanged: (v) => chosen = v),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('alpha'));
    await tester.pump();

    expect(chosen, 'alpha', reason: 'the row must be tappable');
  });

  testWidgets('a row excluded by requireDomain says why', (tester) async {
    String? chosen;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IdentityPicker(
            selectedId: null,
            onChanged: (v) => chosen = v,
            requireDomain: 'example.com',
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('alpha'));
    await tester.pump();
    expect(chosen, 'alpha', reason: 'a matching identity stays selectable');

    chosen = null;
    await tester.tap(find.text('beta'), warnIfMissed: false);
    await tester.pump();
    expect(chosen, isNull, reason: 'a non-matching identity is not selectable');
  });
}
