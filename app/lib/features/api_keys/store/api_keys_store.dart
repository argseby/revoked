import 'package:mobx/mobx.dart';

import 'package:revoked_app/core/config/app_config.dart';
import 'package:revoked_app/core/models/api_key.dart';
import 'package:revoked_app/core/network/api_client.dart';
import 'package:revoked_app/core/state/observable_text_controller.dart';

part 'api_keys_store.g.dart';

/// API keys for the active workspace.
// ignore: library_private_types_in_public_api
class ApiKeysStore = _ApiKeysStore with _$ApiKeysStore;

abstract class _ApiKeysStore with Store {
  final ApiClient _api;

  _ApiKeysStore(this._api);

  String get _basePath =>
      '/api/collections/${AppConfig.apiKeysCollection}/records';

  final ObservableList<ApiKey> apiKeys = ObservableList<ApiKey>();

  @observable
  bool isLoading = false;

  @observable
  String? errorMessage;

  /// The plaintext of the key just created, from the X-Plain-Token header —
  /// shown once, never retrievable again.
  @observable
  String? lastCreatedPlainToken;

  final ObservableTextController draftLabel = ObservableTextController();

  final ObservableSet<String> draftScopes = ObservableSet<String>();

  /// Days until the key stops working; null means it never expires.
  @observable
  int? draftExpiresInDays = 90;

  @computed
  bool get canCreateDraft =>
      draftLabel.text.trim().isNotEmpty && draftScopes.isNotEmpty;

  @action
  void resetDraft() {
    draftLabel.clear();
    draftScopes.clear();
    draftExpiresInDays = 90;
  }

  @action
  void toggleDraftScope(String key, bool on) {
    if (on) {
      draftScopes.add(key);
    } else {
      draftScopes.remove(key);
    }
  }

  @action
  void setDraftExpiry(int? days) => draftExpiresInDays = days;

  @action
  Future<void> loadApiKeys() async {
    isLoading = true;
    errorMessage = null;
    try {
      final data = await _api.get(
        _basePath,
        queryParams: {'page': '1', 'perPage': '50', 'sort': '-created'},
      );
      final items = (data['items'] as List<dynamic>?) ?? [];
      apiKeys
        ..clear()
        ..addAll(items.map((e) => ApiKey.fromJson(e as Map<String, dynamic>)));
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isLoading = false;
    }
  }

  @action
  Future<bool> createApiKey({
    required String label,
    required String user,
    required String workspace,
    required List<String> scopes,
    String? expiresAt,
  }) async {
    isLoading = true;
    errorMessage = null;
    lastCreatedPlainToken = null;
    try {
      final response = await _api.postWithHeaders(
        _basePath,
        body: {
          'label': label,
          'user': user,
          'workspace': workspace,
          'scopes': scopes,
          if (expiresAt != null && expiresAt.isNotEmpty) 'expiresAt': expiresAt,
        },
      );
      final plainToken =
          response.headers['x-plain-token'] ??
          response.headers['X-Plain-Token'];
      final key = ApiKey.fromJson(
        response.body as Map<String, dynamic>,
        plainToken: plainToken,
      );
      apiKeys.insert(0, key);
      lastCreatedPlainToken = key.plainToken;
      return true;
    } catch (e) {
      errorMessage = e.toString();
      return false;
    } finally {
      isLoading = false;
    }
  }

  @action
  Future<void> deleteApiKey(String id) async {
    isLoading = true;
    errorMessage = null;
    try {
      await _api.delete('$_basePath/$id');
      apiKeys.removeWhere((k) => k.id == id);
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isLoading = false;
    }
  }

  @action
  void clearLastToken() => lastCreatedPlainToken = null;
}
