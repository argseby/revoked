import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobx/mobx.dart';
import 'package:revoked_app/core/models/invite.dart';
import 'package:revoked_app/core/models/trust_verdict.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/widgets/invite_trust_summary.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Anyone can host this service and put any address in an invite, so what the
/// screen says about that address must depend on whether the domain behind it
/// was actually proven.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Stores.init();
  });

  InvitePreview previewWith({
    String emailDomain = 'bmw.example',
    bool matches = true,
    bool canStillInvite = true,
  }) => InvitePreview.fromJson({
    'label': '',
    'permissions': <dynamic>[],
    'workspace': {'name': 'BMW'},
    'server': {'domain': 'bmw.example', 'rootFingerprint': 'ab' * 32},
    'inviter': {
      'email': 'alice@$emailDomain',
      'emailDomain': emailDomain,
      'serverDomain': 'bmw.example',
      'emailMatchesServer': matches,
      'canStillInvite': canStillInvite,
    },
  });

  Future<void> show(WidgetTester tester, InvitePreview preview) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: InviteTrustSummary(preview: preview),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  void setVerdict(TrustVerdict? verdict) {
    runInAction(() {
      Stores.invites.inviteTrustVerdict = verdict;
      Stores.invites.isVerifyingInviteTrust = false;
    });
  }

  testWidgets('an unverified domain makes the address an unbacked claim', (
    tester,
  ) async {
    setVerdict(
      TrustVerdict.dnsMissing(domain: 'bmw.example', reason: 'no TXT record'),
    );
    await show(tester, previewWith());

    expect(find.textContaining('alice@bmw.example'), findsOneWidget);
    expect(
      find.textContaining('only what the server says it is'),
      findsOneWidget,
    );
    // The reassuring wording belongs to a proven domain and must not appear.
    expect(find.textContaining('is DNS-verified'), findsNothing);
  });

  testWidgets('a verified domain backs an address inside it', (tester) async {
    setVerdict(
      TrustVerdict.verified(
        domain: 'bmw.example',
        rootFingerprint: 'ab' * 32,
        identityFingerprint: 'cd' * 32,
      ),
    );
    await show(tester, previewWith());

    expect(find.textContaining('is DNS-verified'), findsOneWidget);
    expect(
      find.textContaining('only what the server says it is'),
      findsNothing,
    );
  });

  testWidgets('a verified domain still does not vouch for an outside address', (
    tester,
  ) async {
    setVerdict(
      TrustVerdict.verified(
        domain: 'bmw.example',
        rootFingerprint: 'ab' * 32,
        identityFingerprint: 'cd' * 32,
      ),
    );
    await show(tester, previewWith(emailDomain: 'gmail.com', matches: false));

    expect(find.textContaining('cannot vouch for the address'), findsOneWidget);
  });

  testWidgets('an inviter who lost the authority is called out', (
    tester,
  ) async {
    setVerdict(
      TrustVerdict.verified(
        domain: 'bmw.example',
        rootFingerprint: 'ab' * 32,
        identityFingerprint: 'cd' * 32,
      ),
    );
    await show(tester, previewWith(canStillInvite: false));

    expect(find.text('The inviter lost this authority'), findsOneWidget);
  });
}
