import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:revoked_sign_in/revoked_sign_in.dart';

/// The service's start and wait routes, answering as told.
class FakeService {
  int starts = 0;
  int asks = 0;
  bool startFails = false;

  /// pending, done, declined or expired.
  String waitAnswer = 'pending';

  late final http.Client client = MockClient((req) async {
    if (req.url.path == '/start') {
      starts++;
      if (startFails) return http.Response('', 500);
      return _json({'app_link': 'revoked://signin?state=s$starts', 'check_code': '0D2-99B', 'wait': 'w$starts'});
    }
    asks++;
    return switch (waitAnswer) {
      'done' => _json({'done': true, 'session': 's1'}),
      'declined' => _json({'done': true, 'error': 'access_denied'}),
      'expired' => http.Response('', 401),
      _ => _json({'done': false}),
    };
  });

  static http.Response _json(Object body) => http.Response(jsonEncode(body), 200);
}

final _start = Uri.parse('https://game.example/start');
final _wait = Uri.parse('https://game.example/wait');

Widget _app(Widget child, {bool reduceMotion = false}) {
  return WidgetsApp(
    color: const Color(0xFF000000),
    textStyle: const TextStyle(color: Color(0xFF191C20), fontSize: 14),
    pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) =>
        PageRouteBuilder<T>(settings: settings, pageBuilder: (context, _, _) => builder(context)),
    builder: (context, page) =>
        reduceMotion ? MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: page!) : page!,
    home: ColoredBox(
      color: const Color(0xFFFFFFFF),
      child: Center(child: child),
    ),
  );
}

RevokedSignInButton _button(
  FakeService service, {
  RevokedLabel label = RevokedLabel.continueWith,
  RevokedTheme theme = RevokedTheme.black,
  RevokedSize size = RevokedSize.medium,
  Locale? locale,
  List<Uri>? opened,
  ValueChanged<Map<String, dynamic>>? onSignedIn,
  ValueChanged<RevokedSignInProblem>? onProblem,
}) {
  return RevokedSignInButton(
    start: _start,
    wait: _wait,
    label: label,
    theme: theme,
    size: size,
    locale: locale,
    httpClient: service.client,
    openApp: (link) async {
      opened?.add(link);
      return true;
    },
    onSignedIn: onSignedIn ?? (_) {},
    onProblem: onProblem,
  );
}

/// Lets the fake routes answer and the panel fade in or out. The panel's
/// waiting mark keeps moving, so pumpAndSettle would never finish.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// One round of asking the wait route.
Future<void> _askOnce(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 2));
  await _settle(tester);
}

final _desktop = TargetPlatformVariant.only(TargetPlatform.macOS);
const _scan = 'Scan this code with the Revoked app on your phone.';

void main() {
  group('look', () {
    testWidgets('sizes are at least 36, 44 and 52 high', (tester) async {
      for (final (size, height) in [(RevokedSize.small, 36.0), (RevokedSize.medium, 44.0), (RevokedSize.large, 52.0)]) {
        await tester.pumpWidget(_app(_button(FakeService(), size: size)));
        expect(tester.getSize(find.byType(RevokedSignInButton)).height, height);
      }
    }, variant: _desktop);

    testWidgets('on Android the touch area is 48 high, even for the small size', (tester) async {
      await tester.pumpWidget(_app(_button(FakeService(), size: RevokedSize.small)));
      expect(tester.getSize(find.byType(RevokedSignInButton)).height, 48);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('icon only is square and named with the full label', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_app(_button(FakeService(), label: RevokedLabel.iconOnly)));
      expect(tester.getSize(find.byType(RevokedSignInButton)), const Size(44, 44));
      expect(find.text('Continue with Revoked'), findsNothing);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Continue with Revoked')),
        matchesSemantics(
          label: 'Continue with Revoked',
          isButton: true,
          isEnabled: true,
          hasEnabledState: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );
      semantics.dispose();
    }, variant: _desktop);

    testWidgets('every label, in English and German', (tester) async {
      final cases = {
        (RevokedLabel.continueWith, null): 'Continue with Revoked',
        (RevokedLabel.signIn, null): 'Sign in with Revoked',
        (RevokedLabel.signUp, null): 'Sign up with Revoked',
        (RevokedLabel.continueWith, const Locale('de')): 'Weiter mit Revoked',
        (RevokedLabel.signUp, const Locale('de')): 'Mit Revoked registrieren',
      };
      for (final MapEntry(key: (label, locale), value: text) in cases.entries) {
        await tester.pumpWidget(_app(_button(FakeService(), label: label, locale: locale)));
        expect(find.text(text), findsOneWidget);
      }
    });
  });

  group('signing in', () {
    testWidgets('on a computer: the panel leads with the code, then signs in', (tester) async {
      final service = FakeService();
      final opened = <Uri>[];
      Map<String, dynamic>? answer;
      await tester.pumpWidget(_app(_button(service, opened: opened, onSignedIn: (a) => answer = a)));

      await tester.tap(find.text('Continue with Revoked'));
      await _settle(tester);
      expect(service.starts, 1);
      expect(find.text(_scan), findsOneWidget);
      expect(find.text('Waiting for approval…'), findsOneWidget);
      expect(find.textContaining('0D2-99B', findRichText: true), findsOneWidget);
      expect(opened, isEmpty, reason: 'a computer does not open the app on its own');

      await tester.tap(find.text('Open Revoked on this device'));
      expect(opened.single.toString(), 'revoked://signin?state=s1');

      await _askOnce(tester);
      expect(answer, isNull);
      service.waitAnswer = 'done';
      await _askOnce(tester);
      expect(answer, {'done': true, 'session': 's1'});
      expect(find.text(_scan), findsNothing);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'RevokedSignInButton');
    }, variant: _desktop);

    testWidgets('on a phone: the app opens at once and the panel leads with opening it', (tester) async {
      final service = FakeService();
      final opened = <Uri>[];
      await tester.pumpWidget(_app(_button(service, opened: opened)));

      await tester.tap(find.text('Continue with Revoked'));
      await _settle(tester);
      expect(opened.single.toString(), 'revoked://signin?state=s1');
      final open = tester.getTopLeft(find.text('Open Revoked'));
      final qrText = tester.getTopLeft(find.text('On another device? Scan this code there.'));
      expect(open.dy, lessThan(qrText.dy));

      await tester.tap(find.byKey(const ValueKey('revoked-close')));
      await _settle(tester);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('the check code is read out one character at a time', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_app(_button(FakeService())));
      await tester.tap(find.text('Continue with Revoked'));
      await _settle(tester);
      expect(find.bySemanticsLabel('Approve only if the app shows 0 D 2, 9 9 B.'), findsOneWidget);
      expect(find.bySemanticsLabel('QR code to sign in with Revoked'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _settle(tester);
      semantics.dispose();
    }, variant: _desktop);

    testWidgets('an expired sign-in offers to start again in the panel', (tester) async {
      final service = FakeService()..waitAnswer = 'expired';
      final problems = <RevokedSignInProblem>[];
      await tester.pumpWidget(_app(_button(service, onProblem: problems.add)));

      await tester.tap(find.text('Continue with Revoked'));
      await _settle(tester);
      await _askOnce(tester);
      expect(find.text('This sign-in has expired.'), findsOneWidget);
      expect(find.text('Waiting for approval…'), findsNothing);
      expect(problems, [RevokedSignInProblem.expired]);

      service.waitAnswer = 'pending';
      await tester.tap(find.text('Start again'));
      await _settle(tester);
      expect(service.starts, 2);
      expect(find.text(_scan), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('revoked-close')));
      await _settle(tester);
      expect(find.text(_scan), findsNothing);
    }, variant: _desktop);

    testWidgets('a decline closes the panel and says so under the button', (tester) async {
      final service = FakeService()..waitAnswer = 'declined';
      final problems = <RevokedSignInProblem>[];
      await tester.pumpWidget(_app(_button(service, onProblem: problems.add)));

      await tester.tap(find.text('Continue with Revoked'));
      await _settle(tester);
      await _askOnce(tester);
      expect(find.text(_scan), findsNothing);
      expect(find.text('Sign-in declined.'), findsOneWidget);
      expect(problems, [RevokedSignInProblem.declined]);
    }, variant: _desktop);

    testWidgets('a failing start route is explained under the button', (tester) async {
      final service = FakeService()..startFails = true;
      await tester.pumpWidget(_app(_button(service)));
      await tester.tap(find.text('Continue with Revoked'));
      await _settle(tester);
      expect(find.text('Signing in didn’t work. Please try again.'), findsOneWidget);
      expect(find.text(_scan), findsNothing);
    }, variant: _desktop);

    testWidgets('the panel speaks German when the button does', (tester) async {
      await tester.pumpWidget(_app(_button(FakeService(), locale: const Locale('de'))));
      await tester.tap(find.text('Weiter mit Revoked'));
      await _settle(tester);
      expect(find.text('Scanne diesen Code mit der Revoked-App auf deinem Handy.'), findsOneWidget);
      expect(find.text('Revoked auf diesem Gerät öffnen'), findsOneWidget);
      expect(find.textContaining('Bestätige nur, wenn die App', findRichText: true), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('revoked-close')));
      await _settle(tester);
    }, variant: _desktop);

    testWidgets('leaving the page with the panel open stops asking', (tester) async {
      final service = FakeService();
      await tester.pumpWidget(_app(_button(service)));
      await tester.tap(find.text('Continue with Revoked'));
      await _settle(tester);
      await tester.pumpWidget(_app(const SizedBox()));
      await _settle(tester);
      final asked = service.asks;
      await _askOnce(tester);
      expect(service.asks, asked);
      expect(find.text(_scan), findsNothing);
    }, variant: _desktop);
  });

  group('keyboard', () {
    testWidgets('Tab reaches the button, Enter presses it, Escape closes the panel', (tester) async {
      final service = FakeService();
      await tester.pumpWidget(_app(_button(service)));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'RevokedSignInButton');

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await _settle(tester);
      expect(service.starts, 1);
      expect(find.text(_scan), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _settle(tester);
      expect(find.text(_scan), findsNothing);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'RevokedSignInButton');
    }, variant: _desktop);

    testWidgets('Space presses it too', (tester) async {
      final service = FakeService();
      await tester.pumpWidget(_app(_button(service)));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await _settle(tester);
      expect(service.starts, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _settle(tester);
    }, variant: _desktop);
  });

  group('accessibility', () {
    testWidgets('meets the Android tap target guideline', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_app(_button(FakeService(), size: RevokedSize.small)));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      semantics.dispose();
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('meets the iOS tap target guideline at the medium size', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_app(_button(FakeService(), label: RevokedLabel.iconOnly)));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      semantics.dispose();
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    for (final theme in [RevokedTheme.black, RevokedTheme.outline]) {
      testWidgets('${theme.name} button is labelled and has enough contrast on a light page', (tester) async {
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(_app(_button(FakeService(), theme: theme)));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        semantics.dispose();
      }, variant: _desktop);
    }

    testWidgets('the panel is labelled and has enough contrast', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_app(_button(FakeService())));
      await tester.tap(find.text('Continue with Revoked'));
      await _settle(tester);
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _settle(tester);
      semantics.dispose();
    }, variant: _desktop);

    testWidgets('nothing moves when the platform asks for less motion', (tester) async {
      await tester.pumpWidget(_app(_button(FakeService()), reduceMotion: true));
      await tester.tap(find.text('Continue with Revoked'));
      await _settle(tester);
      expect(find.text(_scan), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
    }, variant: _desktop);
  });
}
