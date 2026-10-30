import 'dart:convert';

import 'package:revoked_app/core/files/file_opener.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mobx/mobx.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:revoked_app/core/config/app_config.dart';
import 'package:revoked_app/core/network/app_errors.dart';
import 'package:revoked_app/core/models/user.dart';
import 'package:revoked_app/core/network/api_client.dart';
import 'package:revoked_app/core/services/secure_storage.dart';
import 'package:revoked_app/core/stores.dart';
import 'package:revoked_app/core/utils/form_factor.dart';
import 'package:revoked_app/core/utils/pkce.dart';
import 'package:revoked_app/core/state/observable_text_controller.dart';

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

/// What the login screen says before the browser opens for a new account.
enum SignupIntro {
  /// On a computer: the phone is the better place, with a code to get there.
  usePhone,

  /// That the browser opens, and that it comes back.
  aboutBrowser,
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
    errorMessage = null;
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
    startedSignup = signup;
    await _writePending({
      'state': state,
      'verifier': verifier,
      'signup': signup,
      'server': _api.baseUrl,
      'at': DateTime.now().millisecondsSinceEpoch,
    });
    final opened = await _openBrowser(page).catchError((Object _) => false);
    runInAction(() {
      isAwaitingBrowser = opened;
      if (!opened) errorMessage = 'Couldn\'t open your browser. Try again.';
    });
    return opened;
  }

  /// "Create account" explains the browser before opening it; on a computer
  /// it first offers the phone.
  @action
  void startSignup() {
    errorMessage = null;
    signupIntro = isMobileDevice
        ? SignupIntro.aboutBrowser
        : SignupIntro.usePhone;
  }

  @action
  void continueSignupHere() => signupIntro = SignupIntro.aboutBrowser;

  @action
  void leaveSignupIntro() => signupIntro = null;

  /// Gives up on a sign-in the browser has not answered.
  @action
  Future<void> cancelSignIn() async {
    isAwaitingBrowser = false;
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
        errorMessage = 'That sign-in took too long. Try again.';
      });
      return false;
    }

    isLoading = true;
    errorMessage = null;
    try {
      final data = await _api.post(
        '/api/passkeys/token',
        body: {'code': code, 'verifier': pending['verifier']},
      );
      final token = data['token'] as String;
      final record = data['record'] as Map<String, dynamic>;
      await _api.saveAuthState(token, record);
      createdAccount = pending['signup'] == true;
      signupIntro = null;
      currentUser = User.fromJson(record);
      return true;
    } catch (e) {
      errorMessage = _parseError(e);
      return false;
    } finally {
      isLoading = false;
      isAwaitingBrowser = false;
    }
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

  /// The name being typed in the name sheet. Owned here, not by the sheet:
  /// the sheet still draws it while it slides away.
  final ObservableTextController nameDraft = ObservableTextController();

  /// Saves the account's own name, which services receive under the
  /// `profile` scope when someone signs in there with Revoked. An empty
  /// name clears it, and services then get the main identity's name.
  ///
  /// Not an `@action`: the store's generated half stays as it is, and the
  /// one observable write is wrapped instead.
  Future<bool> updateName(String name) async {
    final user = currentUser;
    if (user == null) return false;
    try {
      final record = await _api.patch(
        '/api/collections/${AppConfig.usersCollection}/records/${user.id}',
        body: {'name': name.trim()},
      );
      runInAction(
        () => currentUser = User.fromJson(record as Map<String, dynamic>),
      );
      return true;
    } catch (e) {
      runInAction(() => errorMessage = _parseError(e));
      return false;
    }
  }

  @action
  Future<void> logout() async {
    await _api.clearAuthState();
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
          ? 'You\'re the last person who can manage a shared workspace. '
                'Hand it over or remove the other members first.'
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

  String _parseError(dynamic e) {
    // A typed code beats matching on prose: the backend names the reason, and
    // AppErrorMessage already knows how to say it.
    final mapped = AppErrorMessage.fromException(e);
    if (mapped.code.isNotEmpty) return mapped.description;

    if (e.toString().contains('validation_')) {
      return 'Check what you entered and try again.';
    }
    return e
        .toString()
        .replaceAll('ApiException', '')
        .replaceAll('Exception:', '')
        .trim();
  }

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
    currentUser = null;
    errorMessage = 'Your session expired. Sign in again.';
  }
}
