import 'package:flutter/widgets.dart';

import 'style.dart';

/// The button's and the panel's text, in English and German. The same words
/// as the web component, so a service reads the same everywhere.
@immutable
class RevokedStrings {
  const RevokedStrings._({
    required this.continueWith,
    required this.signIn,
    required this.signUp,
    required this.opening,
    required this.scan,
    required this.scanElsewhere,
    required this.open,
    required this.openPhone,
    required this.check,
    required this.waiting,
    required this.close,
    required this.qr,
    required this.startAgain,
    required this.declined,
    required this.expired,
    required this.failed,
  });

  final String continueWith;
  final String signIn;
  final String signUp;
  final String opening;
  final String scan;
  final String scanElsewhere;
  final String open;
  final String openPhone;

  /// Contains `{code}` where the check code goes.
  final String check;
  final String waiting;
  final String close;
  final String qr;
  final String startAgain;
  final String declined;
  final String expired;
  final String failed;

  static const en = RevokedStrings._(
    continueWith: 'Continue with Revoked',
    signIn: 'Sign in with Revoked',
    signUp: 'Sign up with Revoked',
    opening: 'Opening Revoked…',
    scan: 'Scan this code with the Revoked app on your phone.',
    scanElsewhere: 'On another device? Scan this code there.',
    open: 'Open Revoked on this device',
    openPhone: 'Open Revoked',
    check: 'Approve only if the app shows {code}.',
    waiting: 'Waiting for approval…',
    close: 'Close',
    qr: 'QR code to sign in with Revoked',
    startAgain: 'Start again',
    declined: 'Sign-in declined.',
    expired: 'This sign-in has expired.',
    failed: 'Signing in didn’t work. Please try again.',
  );

  static const de = RevokedStrings._(
    continueWith: 'Weiter mit Revoked',
    signIn: 'Mit Revoked anmelden',
    signUp: 'Mit Revoked registrieren',
    opening: 'Revoked wird geöffnet …',
    scan: 'Scanne diesen Code mit der Revoked-App auf deinem Handy.',
    scanElsewhere: 'Auf einem anderen Gerät? Scanne den Code dort.',
    open: 'Revoked auf diesem Gerät öffnen',
    openPhone: 'Revoked öffnen',
    check: 'Bestätige nur, wenn die App {code} zeigt.',
    waiting: 'Warte auf Bestätigung …',
    close: 'Schließen',
    qr: 'QR-Code zum Anmelden mit Revoked',
    startAgain: 'Erneut starten',
    declined: 'Anmeldung abgelehnt.',
    expired: 'Diese Anmeldung ist abgelaufen.',
    failed: 'Die Anmeldung hat nicht geklappt. Bitte versuche es erneut.',
  );

  /// German for `de`, English for everything else.
  static RevokedStrings forLocale(Locale? locale) => locale?.languageCode == 'de' ? de : en;

  /// The label's text. [RevokedLabel.iconOnly] uses the continue wording,
  /// which becomes its accessible name.
  String label(RevokedLabel label) => switch (label) {
    RevokedLabel.continueWith || RevokedLabel.iconOnly => continueWith,
    RevokedLabel.signIn => signIn,
    RevokedLabel.signUp => signUp,
  };
}

/// "0D2-99B" read out one character at a time: "0 D 2, 9 9 B".
String spellCheckCode(String code) => code.split('-').map((group) => group.split('').join(' ')).join(', ');
