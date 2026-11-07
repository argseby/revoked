// A minimal app with the button. Point SERVICE at a service that has the
// start and wait routes, such as examples/sign-in-demo (port 4000 by default):
//
//   flutter run --dart-define=SERVICE=https://shop.example

import 'package:flutter/widgets.dart';
import 'package:revoked_sign_in/revoked_sign_in.dart';

const _service = String.fromEnvironment('SERVICE', defaultValue: 'http://localhost:4000');

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return WidgetsApp(
      color: const Color(0xFF000000),
      textStyle: const TextStyle(color: Color(0xFF191C20), fontSize: 15),
      pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) =>
          PageRouteBuilder<T>(settings: settings, pageBuilder: (context, _, _) => builder(context)),
      home: const _SignInPage(),
    );
  }
}

class _SignInPage extends StatefulWidget {
  const _SignInPage();

  @override
  State<_SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<_SignInPage> {
  Map<String, dynamic>? _answer;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF8F9FF),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              spacing: 16,
              children: [
                RevokedSignInButton(
                  start: Uri.parse('$_service/login/start'),
                  wait: Uri.parse('$_service/login/wait'),
                  expand: true,
                  onSignedIn: (answer) => setState(() => _answer = answer),
                ),
                if (_answer != null) Text('Signed in: $_answer', textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
