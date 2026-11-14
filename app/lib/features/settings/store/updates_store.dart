import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:mobx/mobx.dart';

import 'package:revoked_app/core/config/app_config.dart';
import 'package:revoked_app/core/utils/versions.dart';

part 'updates_store.g.dart';

/// The newest published releases of the app and the server, read from the
/// `version.json` every release attaches, and whether either one here is
/// behind.
// ignore: library_private_types_in_public_api
class UpdatesStore = _UpdatesStore with _$UpdatesStore;

abstract class _UpdatesStore with Store {
  final http.Client _http;
  final String? Function() _serverVersion;

  /// [_serverVersion] is what the signed-in server reports, read live.
  _UpdatesStore({http.Client? httpClient, required this._serverVersion})
    : _http = httpClient ?? http.Client();

  static const _interval = Duration(hours: 6);

  DateTime? _checkedAt;

  @observable
  String? latestApp;

  @observable
  String? latestServer;

  @computed
  bool get appUpdate => _behind(AppConfig.appVersion, latestApp);

  @computed
  bool get serverUpdate => _behind(_serverVersion(), latestServer);

  bool _behind(String? current, String? latest) =>
      current != null &&
      compareVersions(current, latest) == VersionStanding.appBehind;

  /// Asks at most every six hours. A failure leaves the last answer, so being
  /// offline never reports an update that is not there.
  @action
  Future<void> checkIfDue() async {
    final last = _checkedAt;
    if (last != null && DateTime.now().difference(last) < _interval) return;
    _checkedAt = DateTime.now();
    try {
      final resp = await _http
          .get(Uri.parse(AppConfig.latestVersionUrl))
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return;
      final body = jsonDecode(resp.body);
      if (body is! Map<String, dynamic>) return;
      _apply(body['app'] as String?, body['server'] as String?);
    } catch (_) {}
  }

  @action
  void _apply(String? app, String? server) {
    latestApp = app;
    latestServer = server;
  }
}
