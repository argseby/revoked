/// The official "Continue with Revoked" button for Flutter.
///
/// ```dart
/// RevokedSignInButton(
///   start: Uri.parse('https://game.example/auth/revoked/start'),
///   wait: Uri.parse('https://game.example/auth/revoked/wait'),
///   onSignedIn: (answer) => context.go('/home'),
/// )
/// ```
library;

export 'src/button.dart' show RevokedAppOpener, RevokedSignInButton;
export 'src/client.dart';
export 'src/mark.dart' show RevokedMark;
export 'src/panel.dart' show RevokedSignInProblem;
export 'src/strings.dart' show RevokedStrings, spellCheckCode;
export 'src/style.dart' show RevokedLabel, RevokedShape, RevokedSize, RevokedSizeSpec, RevokedTheme;
