import 'dart:convert';

import 'package:revoked_app/core/files/file_opener.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mobx/mobx.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:revoked_app/core/config/app_config.dart';
import 'package:revoked_app/core/network/app_errors.dart';
import 'package:revoked_app/core/models/passkey.dart';
import 'package:revoked_app/core/models/user.dart';
import 'package:revoked_app/core/network/api_client.dart';
import 'package:revoked_app/core/services/secure_storage.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/utils/pkce.dart';
import 'package:revoked_app/features/two_factor/two_factor.dart';

part 'auth_store.g.dart';

/// On Android the page opens in a Custom Tab: a browser tab inside the
/// app, which keeps the person here instead of sending them to another app
/// and back, and which - unlike a web view - can use passkeys. The page's
/// `revoked://auth` answer brings MainActivity forward and closes the tab
/// with it (it is `singleTask`). Without a browser that offers Custom Tabs,
/// and everywhere else, it opens in the browser: url_launcher would fall
/// back to a web view, where passkeys do not work.
Future<bool> openSignInPage(
  Uri page, {
  TargetPlatform? platform,
  Future<bool> Function(LaunchMode mode)? supports,
  Future<bool> Function(Uri page, LaunchMode mode)? launch,
}) async {
  final android = (platform ?? defaultTargetPlatform) == TargetPlatform.android;
  final canTab =
      android &&
      await (supports ?? supportsLaunchMode)(
        LaunchMode.inAppBrowserView,
      ).catchError((Object _) => false);
  final open = launch ?? ((Uri p, LaunchMode m) => launchUrl(p, mode: m));
  return open(
    page,
    canTab ? LaunchMode.inAppBrowserView : LaunchMode.externalApplication,
  );
}

/// What the login screen shows instead of its welcome before the browser
/// opens.
enum SignupIntro {
  /// On a computer: the phone is the better place for a new passkey, with a
  /// code to get there. Offered, never in the way.
  usePhone,
}

/// A passkey sign-in the server answered with `two_factor_required`: the
/// passkey is proven, and the session waits for the authenticator's code.
/// Held in memory only, like the link it came from.
class TwoFactorChallenge {
  final String id;

  /// The `revoked://auth` link the sign-in came back with: its fragment
  /// carries what the passkey derived, handed on once the session exists.
  final Uri link;

  /// Whether the browser was opened to create an account.
  final bool signup;

  const TwoFactorChallenge({
    required this.id,
    required this.link,
    required this.signup,
  });
}

// ignore: library_private_types_in_public_api
class AuthStore = _AuthStore with _$AuthStore;

abstract class _AuthStore with Store {
  final ApiClient _api;

  final FlutterSecureStorage _secure;

  /// Opens the sign-in page ([openSignInPage]); replaced in tests, which
  /// have no browser.
  final Future<bool> Function(Uri page) _openBrowser;

  _AuthStore(
    this._api, {
    FlutterSecureStorage? secureStorage,
    Future<bool> Function(Uri page)? openBrowser,
  }) : _secure = secureStorage ?? createSecureStorage(),
       _openBrowser = openBrowser ?? openSignInPage;

  static const _pendingKey = 'passkey_sign_in_pending';

  /// How long a sign-in started here may take to come back from the browser.
  static const _pendingTtl = Duration(minutes: 15);

  /// True from opening the server's sign-in page until it answers or the
  /// person gives up: the login screen says where to look.
  @observable
  bool isAwaitingBrowser = false;

  @observable
  SignupIntro? signupIntro;

  @observable
  User? currentUser;

  @observable
  bool isLoading = false;

  @observable
  String? errorMessage;

  @observable
  bool isInitialized = false;

  @observable
  bool isDeletingAccount = false;

  /// Set while a sign-in waits for the authenticator's code; the login screen
  /// asks for it ([completeTwoFactor]).
  @observable
  TwoFactorChallenge? twoFactorChallenge;

  /// What went wrong with the last code, shown under the field.
  @observable
  String? twoFactorError;

  /// The server requires an authenticator app and this account has none: the
  /// app shows the enrolment gate before anything else.
  @observable
  bool twoFactorSetupRequired = false;

  @computed
  bool get isAuthenticated => currentUser != null;

  @computed
  String get userEmail => currentUser?.email ?? '';

  @computed
  String get userId => currentUser?.id ?? '';

  @computed
  String? get activeWorkspace => currentUser?.activeWorkspace;

  @action
  Future<void> initialize() async {
    isLoading = true;
    errorMessage = null;
    try {
      // Backstop for the whole restore: `finally` only runs when the
      // awaited future settles, so any hung platform call in the chain
      // would otherwise hold the splash forever.
      currentUser = await _tryRestoreSession().timeout(
        const Duration(seconds: 25),
        onTimeout: () => null,
      );
      if (currentUser != null) await refreshTwoFactorRequirement();
    } catch (e) {
      currentUser = null;
    } finally {
      isLoading = false;
      isInitialized = true;
    }
  }

  /// Opens the server's sign-in page in the browser. People sign in with a
  /// passkey, and a passkey is bound to the server's address — so the page
  /// there talks to the authenticator, and sends the person back with a
  /// one-time code ([completeSignIn]). With [signup] the page starts on
  /// creating an account instead.
  ///
  /// The code is bound to a PKCE challenge made here: nothing else on the
  /// device that sees the `revoked://auth` link can redeem it.
  @action
  Future<bool> beginSignIn({bool signup = false}) async {
    final page = await _prepareSignIn(signup: signup);
    final opened = await _openBrowser(page).catchError((Object _) => false);
    runInAction(() {
      isAwaitingBrowser = opened;
      if (!opened) errorMessage = 'The browser could not be opened.';
    });
    return opened;
  }

  /// The same page as [beginSignIn], handed back instead of opened, for
  /// pasting into another browser on this device. The way back is the
  /// `revoked://auth` link, which only this device's app answers.
  Future<Uri> signInLink() async {
    final page = await _prepareSignIn();
    runInAction(() => isAwaitingBrowser = true);
    return page;
  }

  Future<Uri> _prepareSignIn({bool signup = false}) async {
    runInAction(() {
      errorMessage = null;
      twoFactorChallenge = null;
      twoFactorError = null;
    });
    final verifier = Pkce.randomToken(32);
    final state = Pkce.randomToken(16);
    final page = Uri.parse('${_api.baseUrl}/passkey').replace(
      queryParameters: {
        'mode': signup ? 'signup' : 'signin',
        'challenge': Pkce.challenge(verifier),
        'state': state,
      },
    );
    // Kept across a restart: a phone may drop the app while the browser is
    // in front, and the link that brings it back must still be answerable.
    runInAction(() => startedSignup = signup);
    await _writePending({
      'state': state,
      'verifier': verifier,
      'signup': signup,
      'server': _api.baseUrl,
      'at': DateTime.now().millisecondsSinceEpoch,
    });
    return page;
  }

  /// On a computer, "Use a phone" shows the code that moves
  /// setup to the phone.
  @action
  void showPhoneSetup() {
    errorMessage = null;
    signupIntro = SignupIntro.usePhone;
  }

  @action
  void leaveSignupIntro() => signupIntro = null;

  /// Gives up on a sign-in the browser has not answered.
  @action
  Future<void> cancelSignIn() async {
    isAwaitingBrowser = false;
    twoFactorChallenge = null;
    signupIntro = null;
    await _writePending(null);
  }

  /// Finishes a sign-in from the `revoked://auth?code=…&state=…` link the
  /// server's page sent the person back with. A link this app did not ask
  /// for — no pending sign-in, or another one's state — is ignored.
  @action
  Future<bool> completeSignIn(Uri link) async {
    final code = link.queryParameters['code'] ?? '';
    final state = link.queryParameters['state'] ?? '';
    final pending = await _readPending();
    if (code.isEmpty || pending == null || pending['state'] != state) {
      return false;
    }
    // One answer per question, whatever comes of it.
    await _writePending(null);
    final startedAt = DateTime.fromMillisecondsSinceEpoch(
      pending['at'] as int? ?? 0,
    );
    if (pending['server'] != _api.baseUrl ||
        DateTime.now().difference(startedAt) > _pendingTtl) {
      runInAction(() {
        isAwaitingBrowser = false;
        errorMessage = 'The sign-in timed out.';
      });
      return false;
    }

    isLoading = true;
    errorMessage = null;
    twoFactorChallenge = null;
    twoFactorError = null;
    try {
      final data = await _api.post(
        '/api/passkeys/token',
        body: {'code': code, 'verifier': pending['verifier']},
      );
      await _finishSignIn(link, data, signup: pending['signup'] == true);
      return true;
    } catch (e) {
      // The passkey was right, and the account asks for its authenticator
      // too: no session yet, only a challenge the code completes.
      final challenge = twoFactorChallengeOf(e);
      if (challenge != null) {
        twoFactorChallenge = TwoFactorChallenge(
          id: challenge,
          link: link,
          signup: pending['signup'] == true,
        );
        return false;
      }
      errorMessage = _parseError(e);
      return false;
    } finally {
      isLoading = false;
      isAwaitingBrowser = false;
    }
  }

  /// Completes a sign-in that waits for the authenticator's [code]. A wrong
  /// code leaves the challenge for another try; one the server no longer
  /// knows sends the person back to the start.
  @action
  Future<bool> completeTwoFactor(String code) async {
    final challenge = twoFactorChallenge;
    if (challenge == null) return false;
    final normalized = normalizeTotpCode(code);
    if (normalized == null) {
      twoFactorError = 'The code has six digits.';
      return false;
    }
    isLoading = true;
    twoFactorError = null;
    try {
      final data = await _api.post(
        '/api/passkeys/token/2fa',
        body: {'challenge': challenge.id, 'code': normalized},
      );
      await _finishSignIn(challenge.link, data, signup: challenge.signup);
      twoFactorChallenge = null;
      return true;
    } catch (e) {
      if (e is ApiException &&
          e.code == AppErrorCode.twoFactorChallengeInvalid) {
        twoFactorChallenge = null;
        errorMessage = describeTwoFactorError(e);
      } else {
        twoFactorError = describeTwoFactorError(e);
      }
      return false;
    } finally {
      isLoading = false;
    }
  }

  /// Gives up on a sign-in that waits for the authenticator's code.
  @action
  void cancelTwoFactor() {
    twoFactorChallenge = null;
    twoFactorError = null;
  }

  /// The authenticator app was set up: the enrolment gate opens.
  @action
  void markTwoFactorSetUp() => twoFactorSetupRequired = false;

  /// Asks the server whether this account still has to set up an
  /// authenticator app — the operator may have started requiring one since
  /// the session began. Left as it was when the server cannot say.
  Future<void> refreshTwoFactorRequirement() async {
    try {
      final status = await TwoFactorApi(
        _api,
      ).status().timeout(const Duration(seconds: 10));
      runInAction(() => twoFactorSetupRequired = status.setupRequired);
    } catch (_) {
      // Offline or an older server: nothing to enforce from here.
    }
  }

  /// Stores the session the server answered with and signs in.
  Future<void> _finishSignIn(
    Uri link,
    dynamic data, {
    required bool signup,
  }) async {
    final token = data['token'] as String;
    final record = data['record'] as Map<String, dynamic>;
    await _api.saveAuthState(token, record);
    onPasskeySignIn?.call(
      _passkeySignIn(link, data as Map<String, dynamic>, record),
    );
    // One button leads both ways in; the server says which it was.
    final meta = data['meta'];
    runInAction(() {
      createdAccount = signup || (meta is Map && meta['created'] == true);
      twoFactorSetupRequired =
          meta is Map && meta['twoFactorSetupRequired'] == true;
      signupIntro = null;
      currentUser = User.fromJson(record);
    });
  }

  Future<Map<String, dynamic>?> _readPending() async {
    try {
      final raw = await _secure
          .read(key: _pendingKey)
          .timeout(const Duration(seconds: 5));
      if (raw == null) return null;
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writePending(Map<String, dynamic>? value) async {
    try {
      final op = value == null
          ? _secure.delete(key: _pendingKey)
          : _secure.write(key: _pendingKey, value: jsonEncode(value));
      await op.timeout(const Duration(seconds: 5));
    } catch (_) {
      // Without storage the sign-in cannot be answered; the next try asks
      // again.
    }
  }

  /// Gives the account a signing identity if it has none, so sharing works
  /// without a detour through settings.
  ///
  /// Called once a workspace exists, because an identity is scoped to one. The
  /// keypair is generated on the device and only the public half uploaded — a
  /// server-generated identity would have no private key here and could never
  /// sign. Failure is not fatal: an identity can be created later by hand.
  Future<void> ensureIdentity({String? name}) async {
    if ((activeWorkspace ?? '').isEmpty) return;
    final identities = Stores.identities;
    await identities.loadIdentities();
    if (identities.identities.isNotEmpty) return;
    try {
      final chosen = name?.trim() ?? '';
      await identities.createIdentity(
        name: chosen.isNotEmpty ? chosen : _defaultIdentityName(),
        isPrimary: true,
      );
    } catch (e) {
      debugPrint('Could not provision the first identity: $e');
    }
  }

  String _defaultIdentityName() {
    final email = userEmail;
    if (email.isEmpty) return 'My identity';
    final local = email.split('@').first.trim();
    return local.isEmpty ? 'My identity' : local;
  }

  /// Whether the page now open in the browser was asked to create an account
  /// rather than sign in, so "Open the page again" reopens the same one.
  bool startedSignup = false;

  /// Whether the last sign-in made a new account. The first-run screen then
  /// shows itself as the end of the trip through the browser.
  bool createdAccount = false;

  /// Lets a store that holds decrypted keys drop them on sign-out.
  void Function()? onLoggedOut;

  /// Tells the store that holds encryption keys which passkey signed in, and
  /// the secret its PRF extension derived. Called before [currentUser] changes.
  void Function(PasskeySignIn signIn)? onPasskeySignIn;

  /// The page sends the PRF output in the link's fragment and nowhere else:
  /// `#prf=<base64url>`, empty when the authenticator gave none, absent when
  /// an older page never asked. The server names the passkey in `meta`.
  static PasskeySignIn _passkeySignIn(
    Uri link,
    Map<String, dynamic> data,
    Map<String, dynamic> record,
  ) {
    final fragment = Uri.splitQueryString(link.fragment);
    final meta = data['meta'];
    final passkey = meta is Map ? meta['passkey'] : null;
    return PasskeySignIn(
      user: record['id'] as String? ?? '',
      credentialId: passkey is Map
          ? passkey['credentialId'] as String? ?? ''
          : '',
      name: passkey is Map ? passkey['name'] as String? ?? '' : '',
      secret: _prfSecret(fragment['prf']),
      asked: fragment.containsKey('prf'),
    );
  }

  /// A PRF output is 32 bytes. Anything else is not one, and is dropped rather
  /// than used to derive a weaker key.
  static Uint8List? _prfSecret(String? encoded) {
    if (encoded == null || encoded.isEmpty) return null;
    try {
      final bytes = base64Url.decode(base64Url.normalize(encoded));
      return bytes.length == 32 ? Uint8List.fromList(bytes) : null;
    } on FormatException {
      return null;
    }
  }

  @action
  Future<void> logout() async {
    await _api.clearAuthState();
    onLoggedOut?.call();
    twoFactorSetupRequired = false;
    currentUser = null;
    await purgeOpenedFiles();
  }

  /// Closes the account on the server, which purges everything it could still
  /// be reached through, then drops the local session.
  @action
  Future<bool> deleteAccount() async {
    isDeletingAccount = true;
    errorMessage = null;
    try {
      await _api.delete('/api/account');
      await logout();
      return true;
    } on ApiException catch (e) {
      errorMessage = e.code == AppErrorCode.lastAdminProtected
          ? 'This account is the last administrator of a shared workspace. '
                'Administration must be handed over, or the other members '
                'removed, first.'
          : e.message;
      return false;
    } finally {
      isDeletingAccount = false;
    }
  }

  @action
  void clearError() {
    errorMessage = null;
  }

  /// Swaps in a changed copy of the signed-in account, such as after its
  /// feature set was saved, and keeps the cached record in step so an
  /// offline start shows the same.
  @action
  void replaceUser(User user) {
    currentUser = user;
    final cached = _api.userData;
    if (cached != null && cached['id'] == user.id) {
      cached['features'] = user.features;
    }
  }

  String _parseError(Object e) => describeError(e);

  Future<User?> _tryRestoreSession() async {
    await _api.loadAuthState();
    if (!_api.isAuthenticated) return null;

    final cached = _api.userData;
    try {
      final data = await _api.post(
        '/api/collections/${AppConfig.usersCollection}/auth-refresh',
      );
      final token = data['token'] as String;
      final record = data['record'] as Map<String, dynamic>;
      await _api.saveAuthState(token, record);
      return User.fromJson(record);
    } on ApiException catch (e) {
      // Only the server saying no ends the session. Treating every failure as
      // a rejection signed the user out whenever the app started offline, or
      // the server was briefly unreachable, despite holding valid credentials.
      if (e.statusCode == 401 || e.statusCode == 403) {
        await _api.clearAuthState();
        return null;
      }
      return cached == null ? null : User.fromJson(cached);
    } catch (_) {
      return cached == null ? null : User.fromJson(cached);
    }
  }

  /// Ends the session locally after the server rejected it. Called from
  /// [ApiClient.onUnauthorized], so a 401 anywhere lands on the login screen
  /// instead of a stream of failure toasts.
  @action
  Future<void> handleSessionExpired() async {
    if (currentUser == null) return;
    await _api.clearAuthState();
    onLoggedOut?.call();
    twoFactorSetupRequired = false;
    currentUser = null;
    errorMessage = 'The session has expired.';
  }
}
