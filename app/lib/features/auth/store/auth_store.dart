import 'package:revoked_app/core/state/observable_text_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:mobx/mobx.dart';

import 'package:revoked_app/core/config/app_config.dart';
import 'package:revoked_app/core/network/app_errors.dart';
import 'package:revoked_app/core/models/user.dart';
import 'package:revoked_app/core/network/api_client.dart';
import 'package:revoked_app/core/stores.dart';

part 'auth_store.g.dart';

// ignore: library_private_types_in_public_api
class AuthStore = _AuthStore with _$AuthStore;

abstract class _AuthStore with Store {
  final ApiClient _api;

  _AuthStore(this._api);

  // The sign-in and sign-up fields. Owned here so the screens are stateless
  // and a typed address survives a rebuild.
  final ObservableTextController loginEmail = ObservableTextController();
  final ObservableTextController loginPassword = ObservableTextController();
  final ObservableTextController registerEmail = ObservableTextController();
  final ObservableTextController registerPassword = ObservableTextController();
  final ObservableTextController registerConfirm = ObservableTextController();

  @observable
  User? currentUser;

  @observable
  bool isLoading = false;

  @observable
  String? errorMessage;

  @observable
  bool isInitialized = false;

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
      currentUser = await _tryRestoreSession();
    } catch (e) {
      currentUser = null;
    } finally {
      isLoading = false;
      isInitialized = true;
    }
  }

  @action
  Future<bool> login(String email, String password) async {
    isLoading = true;
    errorMessage = null;
    try {
      currentUser = await _login(email, password);
      return true;
    } catch (e) {
      errorMessage = _parseError(e);
      return false;
    } finally {
      isLoading = false;
    }
  }

  @action
  Future<bool> register(
    String email,
    String password,
    String passwordConfirm,
  ) async {
    isLoading = true;
    errorMessage = null;
    try {
      await _api.post(
        '/api/collections/${AppConfig.usersCollection}/records',
        body: {
          'email': email,
          'password': password,
          'passwordConfirm': passwordConfirm,
        },
      );
      currentUser = await _login(email, password);
      return true;
    } catch (e) {
      errorMessage = _parseError(e);
      return false;
    } finally {
      isLoading = false;
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

  @action
  Future<void> logout() async {
    await _api.clearAuthState();
    currentUser = null;
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

    if (e.toString().contains('Failed to authenticate')) {
      return 'Invalid email or password';
    }
    if (e.toString().contains('validation_')) {
      return 'Please check your input and try again';
    }
    return e
        .toString()
        .replaceAll('ApiException', '')
        .replaceAll('Exception:', '')
        .trim();
  }

  Future<User> _login(String email, String password) async {
    final data = await _api.post(
      '/api/collections/${AppConfig.usersCollection}/auth-with-password',
      body: {'identity': email, 'password': password},
    );
    final token = data['token'] as String;
    final record = data['record'] as Map<String, dynamic>;
    await _api.saveAuthState(token, record);
    return User.fromJson(record);
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
