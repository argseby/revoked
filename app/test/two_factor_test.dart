import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:revoked_app/core/models/passkey.dart';
import 'package:revoked_app/core/network/api_client.dart';
import 'package:revoked_app/features/auth/store/auth_store.dart';
import 'package:revoked_app/features/two_factor/two_factor.dart';
import 'package:revoked_app/features/two_factor/view/two_factor_code_prompt.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response _json(Object body, int status) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('codes', () {
    test('a code is six digits, spaces and dashes aside', () {
      expect(normalizeTotpCode('123456'), '123456');
      expect(normalizeTotpCode(' 123 456 '), '123456');
      expect(normalizeTotpCode('123-456'), '123456');
      expect(normalizeTotpCode('012345'), '012345');
      expect(normalizeTotpCode(''), isNull);
      expect(normalizeTotpCode('12345'), isNull);
      expect(normalizeTotpCode('1234567'), isNull);
      expect(normalizeTotpCode('12a456'), isNull);
      expect(normalizeTotpCode('١٢٣٤٥٦'), isNull);
    });

    test('the field keeps digits only, at most six', () {
      const formatter = TotpCodeFormatter();
      final out = formatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(text: '12 34-56 78'),
      );
      expect(out.text, '123456');
      expect(out.selection.baseOffset, 6);
    });

    test('a secret is grouped in fours', () {
      expect(groupTotpSecret('JBSWY3DPEHPK3PXP'), 'JBSW Y3DP EHPK 3PXP');
      expect(groupTotpSecret('ABCDEF'), 'ABCD EF');
    });

    test('status and setup parse', () {
      final status = TwoFactorStatus.fromJson({
        'enabled': true,
        'required': true,
        'setupRequired': false,
        'enabledAt': '2026-11-08T10:00:00Z',
      });
      expect(status.enabled, isTrue);
      expect(status.required, isTrue);
      expect(status.setupRequired, isFalse);
      expect(status.enabledAt, DateTime.utc(2026, 11, 8, 10));
      final setup = TotpSetup.fromJson({
        'secret': 'S',
        'otpauthUri': 'otpauth://totp/Revoked:a?secret=S',
      });
      expect(setup.otpauthUri, startsWith('otpauth://'));
    });
  });

  group('sign-in', () {
    test(
      'an account with an authenticator app signs in with its code',
      () async {
        SharedPreferences.setMockInitialValues({});
        FlutterSecureStorage.setMockInitialValues({});
        final calls = <String, Map<String, dynamic>>{};
        final api = ApiClient(
          httpClient: MockClient((request) async {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            calls[request.url.path] = body;
            switch (request.url.path) {
              case '/api/passkeys/token':
                return _json({
                  'code': 'two_factor_required',
                  'message': 'Code needed.',
                  'status': 401,
                  'challenge': 'ch-1',
                }, 401);
              case '/api/passkeys/token/2fa':
                if (body['code'] != '123456') {
                  return _json({
                    'code': 'two_factor_code_invalid',
                    'message': 'Wrong.',
                    'status': 401,
                  }, 401);
                }
                return _json({
                  'token': 'session-token',
                  'record': {'id': 'u1', 'email': 'a@example.com'},
                  'meta': {
                    'passkey': {'credentialId': 'cred-1', 'name': 'Phone'},
                  },
                }, 200);
            }
            return _json({}, 404);
          }),
        );
        final opened = <Uri>[];
        final auth = AuthStore(
          api,
          openBrowser: (page) async {
            opened.add(page);
            return true;
          },
        );
        final signIns = <PasskeySignIn>[];
        auth.onPasskeySignIn = signIns.add;

        await auth.beginSignIn();
        final state = opened.single.queryParameters['state']!;
        expect(
          await auth.completeSignIn(
            Uri.parse('revoked://auth?code=c&state=$state'),
          ),
          isFalse,
        );
        // No session yet, and nothing reported as a failure: a code is asked.
        expect(auth.isAuthenticated, isFalse);
        expect(auth.errorMessage, isNull);
        expect(auth.twoFactorChallenge?.id, 'ch-1');

        expect(await auth.completeTwoFactor('12345'), isFalse);
        expect(auth.twoFactorError, isNotNull);
        expect(calls.containsKey('/api/passkeys/token/2fa'), isFalse);

        expect(await auth.completeTwoFactor('654 321'), isFalse);
        expect(auth.twoFactorError, contains('not the one'));
        expect(auth.twoFactorChallenge, isNotNull);

        expect(await auth.completeTwoFactor('123 456'), isTrue);
        expect(calls['/api/passkeys/token/2fa'], {
          'challenge': 'ch-1',
          'code': '123456',
        });
        expect(auth.isAuthenticated, isTrue);
        expect(auth.twoFactorChallenge, isNull);
        expect(auth.twoFactorSetupRequired, isFalse);
        expect(signIns.single.credentialId, 'cred-1');
      },
    );

    test('an expired challenge goes back to the start', () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final api = ApiClient(
        httpClient: MockClient((request) async {
          if (request.url.path == '/api/passkeys/token') {
            return _json({
              'code': 'two_factor_required',
              'message': '',
              'status': 401,
              'challenge': 'ch-1',
            }, 401);
          }
          return _json({
            'code': 'two_factor_challenge_invalid',
            'message': 'Expired.',
            'status': 400,
          }, 400);
        }),
      );
      final opened = <Uri>[];
      final auth = AuthStore(
        api,
        openBrowser: (page) async {
          opened.add(page);
          return true;
        },
      );
      await auth.beginSignIn();
      final state = opened.single.queryParameters['state']!;
      await auth.completeSignIn(
        Uri.parse('revoked://auth?code=c&state=$state'),
      );
      expect(await auth.completeTwoFactor('123456'), isFalse);
      expect(auth.twoFactorChallenge, isNull);
      expect(auth.errorMessage, isNotNull);
    });

    test('a server that requires it says so with the session', () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final api = ApiClient(
        httpClient: MockClient(
          (request) async => _json({
            'token': 'session-token',
            'record': {'id': 'u1', 'email': 'a@example.com'},
            'meta': {'twoFactorSetupRequired': true},
          }, 200),
        ),
      );
      final opened = <Uri>[];
      final auth = AuthStore(
        api,
        openBrowser: (page) async {
          opened.add(page);
          return true;
        },
      );
      await auth.beginSignIn();
      final state = opened.single.queryParameters['state']!;
      expect(
        await auth.completeSignIn(
          Uri.parse('revoked://auth?code=c&state=$state'),
        ),
        isTrue,
      );
      expect(auth.twoFactorSetupRequired, isTrue);
      auth.markTwoFactorSetUp();
      expect(auth.twoFactorSetupRequired, isFalse);
    });
  });

  group('code prompt', () {
    testWidgets('submits once six digits are in', (tester) async {
      final submitted = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TwoFactorCodePrompt(onSubmit: submitted.add)),
        ),
      );

      Future<void> tapSubmit() async {
        await tester.tap(find.byKey(const ValueKey('two-factor-submit')));
        await tester.pump();
      }

      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('two-factor-code')),
          matching: find.byType(EditableText),
        ),
        '123',
      );
      await tester.pump();
      await tapSubmit();
      expect(submitted, isEmpty);

      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('two-factor-code')),
          matching: find.byType(EditableText),
        ),
        '123 456',
      );
      await tester.pump();
      await tapSubmit();
      expect(submitted, ['123456']);
    });

    testWidgets('shows what went wrong with the last code', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TwoFactorCodePrompt(
              onSubmit: (_) {},
              error: 'This code is not the one the app shows.',
            ),
          ),
        ),
      );
      expect(
        find.text('This code is not the one the app shows.'),
        findsOneWidget,
      );
    });
  });

  group('the server side', () {
    test('turning it on keeps the fresh session it hands back', () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final api = ApiClient(
        httpClient: MockClient(
          (request) async => _json({
            'enabled': true,
            'required': false,
            'setupRequired': false,
            'token': 'fresh-token',
          }, 200),
        ),
      );
      await api.saveAuthState('old-token', {'id': 'u1'});
      final status = await TwoFactorApi(api).confirm('123456');
      expect(status.enabled, isTrue);
      expect(api.authToken, 'fresh-token');
    });

    test('a session held until setup tells the app', () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final api = ApiClient(
        httpClient: MockClient(
          (request) async => _json({
            'code': 'two_factor_setup_required',
            'message': 'Set up an authenticator app first.',
            'status': 403,
          }, 403),
        ),
      );
      await api.saveAuthState('token', {'id': 'u1'});
      var told = 0;
      api.onTwoFactorSetupRequired = () => told++;
      await expectLater(
        api.get('/api/collections/records/records'),
        throwsA(isA<ApiException>()),
      );
      expect(told, 1);
    });
  });
}
