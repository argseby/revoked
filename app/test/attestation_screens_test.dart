import 'dart:convert';
import 'dart:io';

import 'package:basic_utils/basic_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pointycastle/export.dart' as pc;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:revoked_app/core/models/presentation_request.dart';
import 'package:revoked_app/core/services/crypto_service.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/theme/app_theme.dart';
import 'package:revoked_app/core/utils/sd_jwt.dart';
import 'package:revoked_app/features/attestations/view/attestation_offer_screen.dart';
import 'package:revoked_app/features/attestations/view/attestations_section.dart';
import 'package:revoked_app/features/attestations/view/presentation_screen.dart';

/// Accepting an offer and presenting a credential both sign with the identity
/// key, which only this device has. These tests play the servers and check
/// what the app sends them: a challenge signed with the right key, and a
/// presentation that carries the ticked claims and nothing else.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final crypto = CryptoService();
  final identity = crypto.generateIdentity(commonName: 'Ada');
  late String credential;

  final claims = <Map<String, dynamic>>[];
  final presented = <Map<String, dynamic>>[];
  final deleted = <String>[];
  final launched = <String>[];
  var offerStatus = 'offered';
  var claimAnswer = 200;
  var serviceRedirect = 'https://shop.test/done?ok=1';

  Map<String, dynamic> credentialRecord() => {
    'id': 'c1',
    'issuer': 'fixture.test',
    'type': 'membership',
    'identity': 'id1',
    'workspace': 'w',
    'credential': credential,
    'claims': {'name': 'Ada Lovelace', 'age_over_18': true, 'member_no': 42},
    'issuedAt': '2027-01-15 08:00:00.000Z',
    'expiresAt': '',
  };

  Future<http.Response> server(http.Request request) async {
    final path = request.url.path;
    http.Response json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

    if (request.url.host == 'shop.test') {
      presented.add(jsonDecode(request.body) as Map<String, dynamic>);
      return json({'redirect_uri': serviceRedirect});
    }
    if (path == '/api/attestations/offers/tok') {
      return json({
        'type': 'membership',
        'label': 'Membership 2027',
        'status': offerStatus,
        if (offerStatus == 'offered')
          'claims': {'name': 'Ada Lovelace', 'age_over_18': true},
        'expiresAt': '',
        'offerExpiresAt': '2027-02-01 00:00:00.000Z',
        'subjectFingerprint': '',
        'server': {'domain': 'club.test', 'rootFingerprint': 'ab' * 32},
        'workspace': {'name': 'The Club'},
      });
    }
    if (path == '/api/attestations/offers/gone') {
      return json({
        'code': 'attestation_offer_expired',
        'message': 'This offer has expired.',
        'status': 410,
      }, 410);
    }
    if (path == '/api/collections/identities/records') {
      return json({
        'items': [
          {
            'id': 'id1',
            'name': 'Ada',
            'certificate': identity.publicKeyPem,
            'fingerprint': 'cd' * 32,
            'user': 'u',
            'workspace': 'w',
            'isPrimary': true,
            'domainAtIssue': 'home.test',
            'status': 'active',
          },
        ],
      });
    }
    if (path == '/api/challenges/attestation/tok') {
      expect(request.url.queryParameters['identityId'], 'id1');
      return json({'nonce': 'nonce-from-the-issuer'});
    }
    if (path == '/api/credentials/claim') {
      claims.add(jsonDecode(request.body) as Map<String, dynamic>);
      if (claimAnswer != 200) {
        return json({
          'code': 'attestation_identity_mismatch',
          'message': 'This offer was made for a different identity.',
          'status': claimAnswer,
        }, claimAnswer);
      }
      return json(credentialRecord());
    }
    if (path == '/api/collections/credentials/records') {
      return json({
        'items': [credentialRecord()],
      });
    }
    if (path == '/api/collections/credentials/records/c1' &&
        request.method == 'DELETE') {
      deleted.add('c1');
      return http.Response('', 204);
    }
    if (path == '/api/credentials/c1/status') {
      return json({
        'state': 'verified',
        'reason': 'fixture.test attests this.',
        'issuerState': 'verified',
        'status': 'valid',
      });
    }
    if (request.url.host == 'ben.test' &&
        path == '/api/public/attestation-checks/chk1') {
      return json({
        'asker': {
          'name': 'Ben',
          'fingerprint': 'ef' * 32,
          'parentSignature': '00',
        },
        'server': {'domain': 'ben.test'},
      });
    }
    if (path == '/api/server') {
      return json({
        'domain': 'home.test',
        'attestations': {'issuing': false},
      });
    }
    return json({'items': <Object>[]});
  }

  setUpAll(() async {
    credential =
        (jsonDecode(File('test/fixtures/sd_jwt.json').readAsStringSync())
                as Map<String, dynamic>)['credential']
            as String;
    SharedPreferences.setMockInitialValues({});
    // The identity's key is on this device, as after creating it here.
    FlutterSecureStorage.setMockInitialValues({
      'identity_priv_id1': identity.privateKeyPem,
    });
    await Stores.init(httpClient: MockClient(server));
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
    claims.clear();
    presented.clear();
    deleted.clear();
    launched.clear();
    offerStatus = 'offered';
    claimAnswer = 200;
    serviceRedirect = 'https://shop.test/done?ok=1';
    Stores.credentials.clearOffer();
  });

  Future<void> open(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.build(Brightness.light), home: screen),
    );
    await tester.pumpAndSettle();
  }

  Uint8List unb64(String s) => base64Url.decode(base64Url.normalize(s));

  testWidgets('an offer shows what it states and is accepted with a signed '
      'challenge', (tester) async {
    await open(tester, const AttestationOfferScreen(token: 'tok'));

    // Who attests and what, before anything is decided.
    expect(find.text('Membership 2027'), findsOneWidget);
    expect(find.text('club.test'), findsOneWidget);
    expect(find.text('The Club'), findsOneWidget);
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('age_over_18'), findsOneWidget);
    expect(find.text('Yes'), findsOneWidget);
    expect(claims, isEmpty, reason: 'looking at an offer accepts nothing');

    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();

    final sent = claims.single;
    expect(sent['token'], 'tok');
    expect(sent['identityId'], 'id1');
    expect(sent['challengeNonce'], 'nonce-from-the-issuer');
    // An offer on the signed-in server names no other server.
    expect(sent.containsKey('origin'), isFalse);
    // Signed with the identity's own key, in the form the server verifies.
    expect(
      crypto.verifySignature(
        publicKeyPem: identity.publicKeyPem,
        message: 'nonce-from-the-issuer',
        signatureBytes: base64.decode(sent['challengeSignature'] as String),
      ),
      isTrue,
    );

    expect(find.text('It’s yours now'), findsOneWidget);
    expect(Stores.credentials.credentials.single.id, 'c1');
  });

  testWidgets('a refusal stays on the offer and says why', (tester) async {
    claimAnswer = 403;
    await open(tester, const AttestationOfferScreen(token: 'tok'));
    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();

    expect(find.text('Made for another identity'), findsOneWidget);
    expect(find.text('It’s yours now'), findsNothing);
    expect(find.text('Accept'), findsOneWidget);
  });

  testWidgets('an offer that is gone says so and offers nothing', (
    tester,
  ) async {
    await open(tester, const AttestationOfferScreen(token: 'gone'));
    expect(find.text('Offer expired'), findsOneWidget);
    expect(find.text('Accept'), findsNothing);
  });

  testWidgets('an offer on another server is relayed with its origin', (
    tester,
  ) async {
    await open(
      tester,
      const AttestationOfferScreen(token: 'tok', origin: 'club.test'),
    );
    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();
    expect(claims.single['origin'], 'https://club.test');
  });

  PresentationRequest request({String claims = 'age_over_18'}) =>
      PresentationRequest.fromQuery({
        'client_id': 'https://shop.test',
        'response_uri': 'https://shop.test/present',
        'nonce': 'shop-nonce-0001',
        'state': 'st-7',
        'type': 'membership',
        'claims': claims,
      })!;

  testWidgets('a presentation carries the ticked claims and nothing else', (
    tester,
  ) async {
    await open(tester, PresentationScreen(request: request()));

    expect(find.text('shop.test asks for an attestation'), findsOneWidget);
    expect(find.text('Asked for'), findsOneWidget);
    // What the service asked for starts ticked; the rest does not.
    expect(find.textContaining('sees 1 detail'), findsOneWidget);

    await tester.tap(find.text('Show it'));
    await tester.pumpAndSettle();

    final sent = presented.single;
    expect(sent['state'], 'st-7');
    final presentation = sent['presentation'] as String;
    final parts = presentation.split('~');
    final parsed = SdJwtCredential.parse(credential);
    expect(parts.first, parsed.jwt);
    expect(parts.length, 3, reason: 'the JWT, one disclosure, the key binding');
    final disclosed = jsonDecode(utf8.decode(unb64(parts[1]))) as List;
    expect(disclosed[1], 'age_over_18');
    for (final withheld in parsed.disclosures.where(
      (d) => d.name != 'age_over_18',
    )) {
      expect(presentation.contains(withheld.raw), isFalse);
    }

    // Bound to this service and this request, with the identity's key.
    final binding = parts.last.split('.');
    final payload = jsonDecode(utf8.decode(unb64(binding[1]))) as Map;
    expect(payload['aud'], 'https://shop.test');
    expect(payload['nonce'], 'shop-nonce-0001');
    expect(payload['sd_hash'], sdDigest('${parts[0]}~${parts[1]}~'));
    final signature = unb64(binding[2]);
    BigInt big(List<int> bytes) =>
        bytes.fold(BigInt.zero, (v, b) => (v << 8) | BigInt.from(b));
    expect(
      CryptoUtils.ecVerify(
        CryptoUtils.ecPublicKeyFromPem(identity.publicKeyPem),
        Uint8List.fromList(utf8.encode('${binding[0]}.${binding[1]}')),
        pc.ECSignature(
          big(signature.sublist(0, 32)),
          big(signature.sublist(32)),
        ),
        algorithm: CryptoService.ecdsaAlgorithm,
      ),
      isTrue,
    );

    // The service's way on is followed, on its own origin.
    expect(find.text('Shown to shop.test'), findsOneWidget);
    expect(launched.single, 'https://shop.test/done?ok=1');
  });

  testWidgets('unticking everything shows the attestation without claims', (
    tester,
  ) async {
    await open(tester, PresentationScreen(request: request()));
    await tester.tap(find.text('age_over_18'));
    await tester.pumpAndSettle();
    expect(find.textContaining('none of its details'), findsOneWidget);

    await tester.tap(find.text('Show it'));
    await tester.pumpAndSettle();
    final parts = (presented.single['presentation'] as String).split('~');
    expect(parts.length, 2, reason: 'the JWT and the key binding only');
  });

  testWidgets('a way on that leaves the service\'s origin is not followed', (
    tester,
  ) async {
    serviceRedirect = 'https://evil.test/collect';
    await open(tester, PresentationScreen(request: request()));
    await tester.tap(find.text('Show it'));
    await tester.pumpAndSettle();

    expect(presented, hasLength(1));
    expect(find.text('Shown to shop.test'), findsOneWidget);
    expect(launched, isEmpty);
    expect(find.textContaining('Continue on'), findsNothing);
  });

  testWidgets('nothing is shown when no held attestation fits', (tester) async {
    final other = PresentationRequest.fromQuery({
      'client_id': 'https://shop.test',
      'response_uri': 'https://shop.test/present',
      'nonce': 'shop-nonce-0001',
      'type': 'verified_adult',
    })!;
    await open(tester, PresentationScreen(request: other));
    expect(find.text('No attestation fits'), findsOneWidget);
    expect(find.text('Show it'), findsNothing);
    expect(presented, isEmpty);
  });

  testWidgets('a malformed request is named as one', (tester) async {
    await open(tester, const PresentationScreen(request: null));
    expect(find.text('This link doesn’t work'), findsOneWidget);
    expect(presented, isEmpty);
  });

  testWidgets('the tab lists what is held, with its claims and standing', (
    tester,
  ) async {
    await Stores.identities.loadIdentities();
    await Stores.credentials.load();
    await Stores.attestations.load();
    await open(
      tester,
      const Scaffold(body: SizedBox(height: 1200, child: IssuedAttestations())),
    );
    // This server's operator did not switch issuing on, and the tab says so
    // in place of a list, with nothing to start.
    expect(find.textContaining('doesn’t issue attestations'), findsOneWidget);
    expect(find.text('Confirm something'), findsNothing);

    await open(
      tester,
      const Scaffold(body: SizedBox(height: 1200, child: HeldAttestations())),
    );
    expect(find.text('membership'), findsOneWidget);
    expect(find.text('From fixture.test · held by Ada'), findsOneWidget);
    // What it states is on the row, before it is opened.
    expect(find.textContaining('member_no: 42'), findsOneWidget);
    expect(find.text('Verified'), findsOneWidget);

    await tester.tap(find.text('membership'));
    await tester.pumpAndSettle();
    expect(find.text('Confirmed by fixture.test'), findsOneWidget);
    // The standing is a pill in the sheet, not only on the row behind it.
    expect(find.text('Verified'), findsNWidgets(2));
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);

    await tester.tap(find.text('Remove attestation'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(deleted, ['c1']);
    expect(Stores.credentials.credentials, isEmpty);
  });

  testWidgets('someone\'s check names who asks, before anything is shown', (
    tester,
  ) async {
    final check = PresentationRequest.fromQuery({
      'client_id': 'https://ben.test',
      'response_uri': 'https://ben.test/api/public/attestation-checks/answer',
      'nonce': 'check-nonce-0001',
      'state': 'chk1',
      'type': 'membership',
    })!;
    await open(tester, PresentationScreen(request: check));
    expect(find.text('Asked by'), findsOneWidget);
    expect(find.text('Ben'), findsOneWidget);
    expect(presented, isEmpty);
  });

  testWidgets('a service\'s request names nobody', (tester) async {
    await open(tester, PresentationScreen(request: request()));
    expect(find.text('Asked by'), findsNothing);
  });
}
