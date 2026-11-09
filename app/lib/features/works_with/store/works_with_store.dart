import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:mobx/mobx.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:revoked_app/core/config/app_config.dart';
import 'package:revoked_app/core/models/works_with.dart';

part 'works_with_store.g.dart';

// ignore: library_private_types_in_public_api
class WorksWithStore = _WorksWithStore with _$WorksWithStore;

/// The services listed in Works with Revoked.
///
/// The list is the reviewed catalog from the repository: a copy ships with
/// the app, so it works offline and on the first start, and a newer copy is
/// read from the repository at most once a day. Only the file is fetched:
/// no search, no tap and nothing about the person leaves the device, and
/// matching a proposal against the list happens here, never at the service.
abstract class _WorksWithStore with Store {
  final http.Client _http;
  final Future<String> Function(String) _loadAsset;
  final DateTime Function() _now;

  _WorksWithStore({
    http.Client? httpClient,
    Future<String> Function(String)? loadAsset,
    DateTime Function()? now,
  }) : _http = httpClient ?? http.Client(),
       // Uncached: the file is read once per start anyway, and a cached
       // future belongs to the zone that first asked, which a widget test
       // throws away between cases.
       _loadAsset =
           loadAsset ?? ((key) => rootBundle.loadString(key, cache: false)),
       _now = now ?? DateTime.now;

  static const asset = 'assets/works_with/catalog.json';
  static const _cacheKey = 'works_with_catalog';
  static const _cacheAtKey = 'works_with_catalog_at';
  static const refreshEvery = Duration(hours: 24);

  @observable
  WorksWithCatalog catalog = WorksWithCatalog.empty;

  /// The newest copy could not be read; the list shown is an older one.
  @observable
  bool refreshFailed = false;

  DateTime? _fetchedAt;

  List<WorksWithService> get services => catalog.services;

  WorksWithService? forOrigin(String origin) => catalog.forOrigin(origin);

  WorksWithService? bySlug(String slug) => catalog.bySlug(slug);

  /// The copy shipped with the app, then the newest one fetched earlier.
  @action
  Future<void> loadLocal() async {
    try {
      final bundled = WorksWithCatalog.parse(await _loadAsset(asset));
      if (bundled != null) catalog = bundled;
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = WorksWithCatalog.parse(prefs.getString(_cacheKey) ?? '');
      final at = prefs.getInt(_cacheAtKey);
      if (cached != null) _use(cached);
      if (at != null) _fetchedAt = DateTime.fromMillisecondsSinceEpoch(at);
    } catch (_) {}
  }

  /// Fetches the catalog from the repository unless a copy is less than a
  /// day old. A failure keeps the list already shown.
  @action
  Future<void> refreshIfDue({bool force = false}) async {
    final last = _fetchedAt;
    if (!force && last != null && _now().difference(last) < refreshEvery) {
      return;
    }
    try {
      final resp = await _http
          .get(Uri.parse(AppConfig.worksWithCatalogUrl))
          .timeout(const Duration(seconds: 8));
      final fetched = resp.statusCode == 200
          ? WorksWithCatalog.parse(resp.body)
          : null;
      if (fetched == null) {
        _failed();
        return;
      }
      _fetchedAt = _now();
      _use(fetched);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, resp.body);
      await prefs.setInt(_cacheAtKey, _fetchedAt!.millisecondsSinceEpoch);
    } catch (_) {
      _failed();
    }
  }

  @action
  void _use(WorksWithCatalog c) {
    catalog = c;
    refreshFailed = false;
  }

  @action
  void _failed() => refreshFailed = true;
}
