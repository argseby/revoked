import 'dart:convert';

import 'package:revoked_app/core/state/observable_text_controller.dart';
import 'package:http/http.dart' as http;
import 'package:mobx/mobx.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:revoked_app/core/config/app_config.dart';
import 'package:revoked_app/core/config/server_blocklist.dart';
import 'package:revoked_app/core/network/api_client.dart';
import 'package:revoked_app/core/utils/versions.dart';

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

  @observable
  bool isSaving = false;

  /// null until a test has run against the current address.
  @observable
  bool? isReachable;

  @observable
  String? testMessage;

  /// The release the address under test reports, once a test reached it.
  @observable
  String? testedVersion;

  /// The release the server in effect reports, once asked.
  @observable
  String? serverVersion;

  @computed
  VersionStanding get versionStanding =>
      compareVersions(AppConfig.appVersion, serverVersion);

  @computed
  bool get canSave => controller.text.trim().isNotEmpty;

  /// Whether the address being typed is the official server.
  @computed
  bool get isOfficial =>
      AppConfig.isOfficialServer(ApiClient.normalizeServerUrl(controller.text));

  String get defaultBaseUrl => _api.defaultBaseUrl;

  /// Editing the address invalidates whatever the last test concluded.
  @action
  void _invalidateReachability() {
    if (isReachable == null && testMessage == null && testedVersion == null) {
      return;
    }
    isReachable = null;
    testMessage = null;
    testedVersion = null;
  }

  @action
  void resetToDefault() => controller.text = _api.defaultBaseUrl;

  @action
  Future<void> test() async {
    final target = ApiClient.normalizeServerUrl(controller.text);
    isTesting = true;
    isReachable = null;
    testMessage = null;
    testedVersion = null;
    if (await _isBlocked(target)) {
      _refuseBlocked(target);
      return;
    }
    try {
      final resp = await http
          .get(Uri.parse('$target/api/health'))
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) {
        _finish(
          reachable: false,
          message:
              '$target answered with HTTP ${resp.statusCode}. Check the address.',
        );
        return;
      }
      _finish(
        reachable: true,
        message: 'Connected to $target',
        version: await _versionAt(target),
      );
    } catch (_) {
      _finish(
        reachable: false,
        message: 'Couldn\'t reach $target. Check the address.',
      );
    }
  }

  /// Persists the address the field currently holds and returns it
  /// normalized, or returns null when it is listed as an impersonation.
  @action
  Future<String?> save() async {
    final target = ApiClient.normalizeServerUrl(controller.text);
    isSaving = true;
    try {
      if (await _isBlocked(target)) {
        _refuseBlocked(target);
        return null;
      }
      final saved = await _api.setBaseUrl(controller.text);
      savedBaseUrl = saved;
      serverVersion = await _versionAt(saved);
      return saved;
    } finally {
      isSaving = false;
    }
  }

  @action
  Future<void> loadServerVersion() async {
    serverVersion = await _versionAt(_api.baseUrl);
  }

  /// What `/api/server` says it was built from; null for a server too old to
  /// say, or one that does not answer.
  Future<String?> _versionAt(String base) async {
    try {
      final resp = await http
          .get(Uri.parse('$base/api/server'))
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return null;
      final version =
          (jsonDecode(resp.body) as Map<String, dynamic>)['version'];
      return version is String && version.isNotEmpty ? version : null;
    } catch (_) {
      return null;
    }
  }

  ServerBlocklist? _blocklist;
  String? _blocklistServer;

  Future<bool> _isBlocked(String target) async {
    final host = Uri.tryParse(target)?.host ?? '';
    return (await _loadBlocklist()).blocks(host);
  }

  /// The project's list together with the current server's own. A server's
  /// list only ever adds to the project's: one that could replace it could
  /// lift the block on its own impersonators.
  Future<ServerBlocklist> _loadBlocklist() async {
    final server = _api.baseUrl;
    final cached = _blocklist;
    if (cached != null && _blocklistServer == server) return cached;
    final lists = await Future.wait([
      _fetchList(AppConfig.blockedDomainsUrl, 'blocked_domains'),
      _fetchList('$server/api/blocked-domains', 'blocked_domains:$server'),
    ]);
    final list = ServerBlocklist.parse(lists.map((l) => l.$1).join('\n'));
    if (lists.every((l) => l.$2)) {
      _blocklist = list;
      _blocklistServer = server;
    }
    return list;
  }

  /// A list and whether it is fresh. Offline, the copy fetched last applies;
  /// a server too old to publish a list has none.
  Future<(String, bool)> _fetchList(String url, String cacheKey) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final resp = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        await prefs.setString(cacheKey, resp.body);
        return (resp.body, true);
      }
      if (resp.statusCode == 404) return ('', true);
    } catch (_) {}
    return (prefs.getString(cacheKey) ?? '', false);
  }

  @action
  void _refuseBlocked(String target) => _finish(
    reachable: false,
    message:
        '${Uri.tryParse(target)?.host ?? target} is a known fake of '
        'Revoked. The official server is ${AppConfig.officialServerHost}.',
  );

  @action
  void _finish({
    required bool reachable,
    required String message,
    String? version,
  }) {
    isTesting = false;
    isReachable = reachable;
    testMessage = message;
    testedVersion = version;
  }
}
