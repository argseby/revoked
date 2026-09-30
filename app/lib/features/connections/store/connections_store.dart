import 'package:mobx/mobx.dart';
import 'package:revoked_app/core/config/app_config.dart';
import 'package:revoked_app/core/models/connection.dart';
import 'package:revoked_app/core/models/link.dart';
import 'package:revoked_app/core/network/api_client.dart';

part 'connections_store.g.dart';

// ignore: library_private_types_in_public_api
class ConnectionsStore = _ConnectionsStore with _$ConnectionsStore;

/// The tools connected to the active workspace, and the links each one's
/// proposals became.
abstract class _ConnectionsStore with Store {
  final ApiClient _api;

  _ConnectionsStore(this._api);

  String get _basePath =>
      '/api/collections/${AppConfig.connectionsCollection}/records';

  String get _linksPath =>
      '/api/collections/${AppConfig.linksCollection}/records';

  @observable
  ObservableList<Connection> connections = ObservableList<Connection>();

  /// Links by the connection they came from.
  @observable
  ObservableMap<String, List<Link>> linksByConnection =
      ObservableMap<String, List<Link>>();

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
        _basePath,
        queryParams: {'sort': '-created', 'perPage': '100'},
      );
      final items = (data['items'] as List<dynamic>?) ?? [];
      final loaded = items
          .map((e) => Connection.fromJson(e as Map<String, dynamic>))
          .toList();

      final linkData = await _api.get(
        _linksPath,
        queryParams: {
          'filter': 'connection != ""',
          'sort': '-created',
          'perPage': '500',
        },
      );
      final byConnection = <String, List<Link>>{};
      for (final e in (linkData['items'] as List<dynamic>?) ?? []) {
        final link = Link.fromJson(e as Map<String, dynamic>);
        byConnection.putIfAbsent(link.connection, () => []).add(link);
      }

      connections = ObservableList.of(loaded);
      linksByConnection = ObservableMap.of(byConnection);
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isLoading = false;
    }
  }

  /// The live connection this workspace has with the tool at [origin], if
  /// any. A lapsed one counts as none, so the tool is asked to connect again.
  Future<Connection?> findByClient(String origin) async {
    try {
      // The origin passed the same pattern the server enforces, so it holds
      // no quote to break out of the filter.
      final data = await _api.get(
        _basePath,
        queryParams: {'filter': 'clientId = "$origin"', 'perPage': '1'},
      );
      final items = (data['items'] as List<dynamic>?) ?? [];
      if (items.isEmpty) return null;
      final found = Connection.fromJson(items.first as Map<String, dynamic>);
      return found.isExpired ? null : found;
    } catch (_) {
      return null;
    }
  }

  /// Connects the tool, or reuses its connection, and returns the one-time
  /// code for its return address. Null when the server refused.
  ///
  /// With [reuse] the owner is not being asked: another of their browsers is
  /// let into a connection that is already live, which stays exactly as it
  /// is — same permissions, same expiry. The server refuses when there is
  /// none, and the owner has to be asked after all.
  ///
  /// With [poll] the code is not for anyone to carry: the page that asked
  /// collects the answer from the server with its own verifier.
  Future<({String code, String connectionId})?> authorize({
    required String clientId,
    required String clientName,
    required String redirectUri,
    required String challenge,
    bool? allowRevoke,
    bool? allowHandOver,
    bool reuse = false,
    bool poll = false,
  }) async {
    errorMessage = null;
    try {
      final data = await _api.post(
        '/api/connections/authorize',
        body: {
          'clientId': clientId,
          'clientName': clientName,
          'redirectUri': redirectUri,
          'challenge': challenge,
          if (reuse) 'reuse': true,
          if (poll) 'poll': true,
          if (!reuse) 'allowRevoke': ?allowRevoke,
          if (!reuse) 'allowHandOver': ?allowHandOver,
        },
      );
      return (
        code: data['code'] as String,
        connectionId: data['connectionId'] as String,
      );
    } catch (e) {
      runInAction(() => errorMessage = e.toString());
      return null;
    }
  }

  /// Ends the connection: every token the tool holds stops working. Links it
  /// proposed stay the owner's and keep working until revoked.
  @action
  Future<bool> disconnect(String id) async {
    errorMessage = null;
    try {
      await _api.delete('$_basePath/$id');
      connections.removeWhere((c) => c.id == id);
      linksByConnection.remove(id);
      return true;
    } catch (e) {
      errorMessage = e.toString();
      return false;
    }
  }

  /// Changes what the owner allows the tool: revoking the links it proposed,
  /// receiving links. A value left null stays as it is.
  @action
  Future<bool> setPermissions(
    String id, {
    bool? allowRevoke,
    bool? allowHandOver,
  }) async {
    errorMessage = null;
    try {
      final data = await _api.post(
        '/api/connections/$id/permissions',
        body: {'allowRevoke': ?allowRevoke, 'allowHandOver': ?allowHandOver},
      );
      final i = connections.indexWhere((c) => c.id == id);
      if (i >= 0) {
        final c = connections[i];
        connections[i] = Connection(
          id: c.id,
          clientId: c.clientId,
          clientName: c.clientName,
          allowRevoke: data['allowRevoke'] as bool? ?? c.allowRevoke,
          allowHandOver: data['allowHandOver'] as bool? ?? c.allowHandOver,
          expiresAt: c.expiresAt,
          lastUsedAt: c.lastUsedAt,
          created: c.created,
        );
      }
      return true;
    } catch (e) {
      errorMessage = e.toString();
      return false;
    }
  }

  /// Revokes a link a tool proposed — the only undo for one that was handed
  /// over.
  @action
  Future<bool> revokeLink(Link link) async {
    errorMessage = null;
    try {
      final data = await _api.patch(
        '$_linksPath/${link.id}',
        body: {'status': 'revoked'},
      );
      final updated = Link.fromJson(data as Map<String, dynamic>);
      final list = [...?linksByConnection[link.connection]];
      final i = list.indexWhere((l) => l.id == link.id);
      if (i >= 0) list[i] = updated;
      linksByConnection[link.connection] = list;
      return true;
    } catch (e) {
      errorMessage = e.toString();
      return false;
    }
  }
}
