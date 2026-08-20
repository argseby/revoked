import 'package:revoked_app/core/state/observable_text_controller.dart';
import 'package:http/http.dart' as http;
import 'package:mobx/mobx.dart';

import 'package:revoked_app/core/network/api_client.dart';

part 'server_settings_store.g.dart';

/// Which backend the app talks to, and whether it answered when last tested.
///
/// A singleton like every other store: the drawer that edits this is opened
/// and closed repeatedly from the login screen, and a half-typed address
/// should survive that.
// ignore: library_private_types_in_public_api
class ServerSettingsStore = _ServerSettingsStore with _$ServerSettingsStore;

abstract class _ServerSettingsStore with Store {
  final ApiClient _api;

  _ServerSettingsStore(this._api) {
    savedBaseUrl = _api.baseUrl;
    controller = ObservableTextController(text: _api.baseUrl);
    controller.addListener(_invalidateReachability);
  }

  /// Owned here rather than by the view, so the text outlives the drawer.
  late final ObservableTextController controller;

  /// The address actually in effect, as opposed to what is being typed.
  @observable
  String savedBaseUrl = '';

  /// Just the host:port, for the "Server: …" label on the auth screens.
  @computed
  String get savedLabel =>
      Uri.tryParse(savedBaseUrl)?.authority ?? savedBaseUrl;

  @observable
  bool isTesting = false;

  /// null until a test has run against the current address.
  @observable
  bool? isReachable;

  @observable
  String? testMessage;

  @computed
  bool get canSave => controller.text.trim().isNotEmpty;

  String get defaultBaseUrl => _api.defaultBaseUrl;

  /// Editing the address invalidates whatever the last test concluded.
  @action
  void _invalidateReachability() {
    if (isReachable == null && testMessage == null) return;
    isReachable = null;
    testMessage = null;
  }

  @action
  void resetToDefault() => controller.text = _api.defaultBaseUrl;

  @action
  Future<void> test() async {
    final target = ApiClient.normalizeServerUrl(controller.text);
    isTesting = true;
    isReachable = null;
    testMessage = null;
    try {
      final resp = await http
          .get(Uri.parse('$target/api/health'))
          .timeout(const Duration(seconds: 5));
      _finish(
        reachable: resp.statusCode == 200,
        message: resp.statusCode == 200
            ? 'Connected to $target'
            : 'Reached $target but got HTTP ${resp.statusCode}',
      );
    } catch (_) {
      _finish(reachable: false, message: 'Could not reach $target');
    }
  }

  /// Persists the address the field currently holds and returns it normalized.
  @action
  Future<String> save() async {
    final saved = await _api.setBaseUrl(controller.text);
    savedBaseUrl = saved;
    return saved;
  }

  @action
  void _finish({required bool reachable, required String message}) {
    isTesting = false;
    isReachable = reachable;
    testMessage = message;
  }
}
