import 'package:mobx/mobx.dart';
import 'package:revoked_app/core/config/app_config.dart';
import 'package:revoked_app/core/models/passkey.dart';
import 'package:revoked_app/core/network/api_client.dart';

part 'passkeys_store.g.dart';

// ignore: library_private_types_in_public_api
class PasskeysStore = _PasskeysStore with _$PasskeysStore;

/// The passkeys the signed-in account can sign in with.
abstract class _PasskeysStore with Store {
  final ApiClient _api;

  _PasskeysStore(this._api);

  @observable
  ObservableList<Passkey> passkeys = ObservableList<Passkey>();

  @observable
  bool isLoading = false;

  @observable
  String? errorMessage;

  @action
  Future<void> load() async {
    isLoading = true;
    errorMessage = null;
    try {
      final data = await _api.get(
        '/api/collections/${AppConfig.passkeysCollection}/records',
        queryParams: {'sort': '-created', 'perPage': '100'},
      );
      final items = (data['items'] as List<dynamic>?) ?? [];
      passkeys = ObservableList.of(
        items.map((e) => Passkey.fromJson(e as Map<String, dynamic>)),
      );
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isLoading = false;
    }
  }

  /// A one-time link to the server's page where this account adds a passkey —
  /// opened here for this device, or passed to another. Null when refused.
  Future<Uri?> addLink() async {
    errorMessage = null;
    try {
      final data = await _api.post('/api/passkeys/tickets');
      return Uri.tryParse(data['url'] as String? ?? '');
    } on ApiException catch (e) {
      runInAction(() => errorMessage = e.message);
      return null;
    } catch (e) {
      runInAction(() => errorMessage = e.toString());
      return null;
    }
  }

  /// Removes a passkey: it stops signing in at once. The server refuses to
  /// take the last one.
  @action
  Future<bool> remove(String id) async {
    errorMessage = null;
    try {
      await _api.delete('/api/passkeys/$id');
      passkeys.removeWhere((p) => p.id == id);
      return true;
    } on ApiException catch (e) {
      errorMessage = e.message;
      return false;
    } catch (e) {
      errorMessage = e.toString();
      return false;
    }
  }
}
