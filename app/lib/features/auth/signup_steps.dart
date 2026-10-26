import 'package:mobx/mobx.dart';

import 'package:revoked_app/core/stores.dart';

/// What the server allows: whether anyone may make an account, and whether a
/// new account confirms its address with a mailed code first.
class SignupPolicy {
  final bool open;
  final bool verifyEmail;

  const SignupPolicy({required this.open, required this.verifyEmail});

  /// A server too old to say: assume the longest way, so the count is never
  /// lower than what the page then asks.
  static const unknown = SignupPolicy(open: true, verifyEmail: true);
}

/// The steps of making an account, the same ones the server's passkey page
/// counts: the email, the code (where the server mails one), the passkey,
/// and the name, which the app asks once the page sends the person back.
///
/// Said on the welcome screen before anything opens, so nobody has to guess
/// how long it takes or where they will be.
abstract final class SignupSteps {
  static final Observable<SignupPolicy?> _policy = Observable(null);

  static SignupPolicy get policy => _policy.value ?? SignupPolicy.unknown;

  /// Reads the policy from the server's public info. A failure leaves the
  /// cautious default in place.
  static Future<void> load() async {
    SignupPolicy? next;
    try {
      final info = await Stores.api.get('/api/server');
      final signups = info is Map<String, dynamic> ? info['signups'] : null;
      if (signups is Map<String, dynamic>) {
        next = SignupPolicy(
          open: signups['open'] == true,
          verifyEmail: signups['verifyEmail'] == true,
        );
      }
    } catch (_) {
      next = null;
    }
    runInAction(() => _policy.value = next);
  }

  /// Each step's name, in order.
  static List<String> get names => [
    'Your email',
    if (policy.verifyEmail) 'The code we email you',
    'A passkey: your fingerprint, face or device PIN',
    'Your name',
  ];

  static int get count => names.length;

  static String get duration =>
      policy.verifyEmail ? 'about 2 minutes' : 'about a minute';
}
