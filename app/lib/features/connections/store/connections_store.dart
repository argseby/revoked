import 'package:mobx/mobx.dart';
import 'package:revoked_app/core/config/app_config.dart';
import 'package:revoked_app/core/models/attestation.dart';
import 'package:revoked_app/core/models/attestation_check.dart';
import 'package:revoked_app/core/models/connection.dart';
import 'package:revoked_app/core/models/invite.dart';
import 'package:revoked_app/core/models/link.dart';
import 'package:revoked_app/core/models/request.dart';
import 'package:revoked_app/core/network/api_client.dart';
import 'package:revoked_app/core/network/app_errors.dart';
import 'package:revoked_app/core/stores.dart';

part 'connections_store.g.dart';

// ignore: library_private_types_in_public_api
class ConnectionsStore = _ConnectionsStore with _$ConnectionsStore;

/// The tools connected to the active workspace, and the links, requests,
/// attestations and checks each one's proposals became.
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
  ObservableMap<String, List<DataRequest>> requestsByConnection =
      ObservableMap<String, List<DataRequest>>();

  @observable
  ObservableMap<String, List<Attestation>> attestationsByConnection =
      ObservableMap<String, List<Attestation>>();

  @observable
  ObservableMap<String, List<AttestationCheck>> checksByConnection =
      ObservableMap<String, List<AttestationCheck>>();

  @observable
  bool isLoading = false;

  @observable
  String? errorMessage;

  /// A pause or activation is on its way.
  @observable
  bool isChanging = false;

  /// The choice in the disconnect dialog: whether the tool's links go too.
  /// It can't be undone, so it starts off every time the dialog opens.
  @observable
  bool revokeLinksOnDisconnect = false;

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

      final [links, requests, attestations, checks] = await Future.wait([
        _fromTools(AppConfig.linksCollection),
        _fromTools(AppConfig.requestsCollection, optional: true),
        _fromTools(AppConfig.attestationsCollection, optional: true),
        _fromTools(AppConfig.attestationChecksCollection, optional: true),
      ]);

      connections = ObservableList.of(loaded);
      linksByConnection = ObservableMap.of(
        _byConnection(links, Link.fromJson, (l) => l.connection),
      );
      requestsByConnection = ObservableMap.of(
        _byConnection(requests, DataRequest.fromJson, (r) => r.connection),
      );
      attestationsByConnection = ObservableMap.of(
        _byConnection(attestations, Attestation.fromJson, (a) => a.connection),
      );
      checksByConnection = ObservableMap.of(
        _byConnection(checks, AttestationCheck.fromJson, (c) => c.connection),
      );
    } catch (e) {
      errorMessage = describeError(e);
    } finally {
      isLoading = false;
    }
  }

  /// The rows of [collection] that came from a tool. An [optional] one a
  /// server older than this app can't filter by tool is left out, so the
  /// tool's links still show.
  Future<List<dynamic>> _fromTools(
    String collection, {
    bool optional = false,
  }) async {
    try {
      final data = await _api.get(
        '/api/collections/$collection/records',
        queryParams: {
          'filter': 'connection != ""',
          'sort': '-created',
          'perPage': '500',
        },
      );
      return (data['items'] as List<dynamic>?) ?? const [];
    } on ApiException {
      if (optional) return const [];
      rethrow;
    }
  }

  static Map<String, List<T>> _byConnection<T>(
    List<dynamic> items,
    T Function(Map<String, dynamic>) parse,
    String Function(T) connection,
  ) {
    final out = <String, List<T>>{};
    for (final e in items) {
      final row = parse(e as Map<String, dynamic>);
      out.putIfAbsent(connection(row), () => []).add(row);
    }
    return out;
  }

  /// The connection this workspace has with the tool at [origin], if any. A
  /// lapsed one counts as none, so the tool is asked to connect again, unless
  /// it is paused: that has to be lifted first.
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
      return found.isExpired && !found.paused ? null : found;
    } catch (_) {
      return null;
    }
  }

  /// The id of the live connection of the tool at [origin], or empty when
  /// there is none it could follow a new row through: not connected, lapsed
  /// or paused.
  Future<String> liveConnectionIdFor(String origin) async {
    if (origin.isEmpty) return '';
    final found = await findByClient(origin);
    if (found == null || found.isExpired || found.paused) return '';
    return found.id;
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
    bool? allowVaultRead,
    List<String>? permissions,
    bool? section,
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
          if (!reuse) 'allowVaultRead': ?allowVaultRead,
          if (!reuse) 'permissions': ?permissions,
          if (!reuse) 'section': ?section,
        },
      );
      return (
        code: data['code'] as String,
        connectionId: data['connectionId'] as String,
      );
    } catch (e) {
      runInAction(() => errorMessage = describeError(e));
      return null;
    }
  }

  /// Ends the connection: every token the tool holds stops working. Links it
  /// proposed are revoked if [revokeLinksOnDisconnect] is set. Otherwise they
  /// stay the owner's and keep working until revoked.
  @action
  Future<bool> disconnect(String id) async {
    errorMessage = null;
    try {
      try {
        await _api.post(
          '/api/connections/$id/disconnect',
          body: {'revokeLinks': revokeLinksOnDisconnect},
        );
      } on ApiException catch (e) {
        // A server older than this app has only the collection's delete, and
        // that can't revoke links, so asking for it has to fail visibly.
        if (e.statusCode != 404 || revokeLinksOnDisconnect) rethrow;
        await _api.delete('$_basePath/$id');
      }
      runInAction(() {
        connections.removeWhere((c) => c.id == id);
        linksByConnection.remove(id);
        requestsByConnection.remove(id);
        attestationsByConnection.remove(id);
        checksByConnection.remove(id);
      });
      return true;
    } catch (e) {
      runInAction(() => errorMessage = describeError(e));
      return false;
    }
  }

  /// Refuses the tool's tokens and pauses its links.
  Future<bool> pause(String id) => _setPaused(id, 'pause');

  /// Undoes [pause]. A link the owner paused themselves stays paused.
  Future<bool> activate(String id) => _setPaused(id, 'resume');

  @action
  Future<bool> _setPaused(String id, String action) async {
    errorMessage = null;
    isChanging = true;
    try {
      await _api.post('/api/connections/$id/$action', body: const {});
      await load();
      return errorMessage == null;
    } catch (e) {
      runInAction(() => errorMessage = describeError(e));
      return false;
    } finally {
      runInAction(() => isChanging = false);
    }
  }

  /// Changes what the owner allows the tool: revoking the links it proposed,
  /// receiving links, reading the vault, its [permissions], its own
  /// [section] and the other [sections] it may read. A value left null stays
  /// as it is. Reading the whole vault can only be withdrawn here; the server
  /// grants it on a new connect alone.
  @action
  Future<bool> setPermissions(
    String id, {
    bool? allowRevoke,
    bool? allowHandOver,
    bool? allowVaultRead,
    List<String>? permissions,
    bool? section,
    List<String>? sections,
  }) async {
    errorMessage = null;
    isChanging = true;
    try {
      final data = await _api.post(
        '/api/connections/$id/permissions',
        body: {
          'allowRevoke': ?allowRevoke,
          'allowHandOver': ?allowHandOver,
          'allowVaultRead': ?allowVaultRead,
          'permissions': ?permissions,
          'section': ?section,
          'sections': ?sections,
        },
      );
      runInAction(() {
        final i = connections.indexWhere((c) => c.id == id);
        if (i >= 0 && data is Map<String, dynamic>) {
          connections[i] = connections[i].withGrant(data);
        }
      });
      return true;
    } catch (e) {
      runInAction(() => errorMessage = describeError(e));
      return false;
    } finally {
      runInAction(() => isChanging = false);
    }
  }

  /// Gives the tool [key] from the catalogue, or takes it away. Changing the
  /// vault keeps the two vault permissions in step: changing implies reading.
  Future<bool> setPermission(
    Connection connection,
    String key,
    bool on,
    List<InvitePermission> catalogue,
  ) {
    final keys = {...connection.permissionKeys(catalogue)};
    if (on) {
      keys.add(key);
      if (key == 'vault:write') keys.add('vault:read');
    } else {
      keys.remove(key);
      if (key == 'vault:read') keys.remove('vault:write');
    }
    return setPermissions(
      connection.id,
      permissions: [
        for (final k in Connection.toolPermissions)
          if (keys.contains(k)) k,
      ],
    );
  }

  /// Gives the tool its section, or takes its access to it away. The section
  /// stays in the vault either way, and comes back as it was.
  Future<bool> setOwnSection(Connection connection, bool on) async {
    final ok = await setPermissions(connection.id, section: on);
    if (ok && on && connection.section.isEmpty) {
      Stores.invalidateLoads();
      await Stores.vault.loadIfDue();
    }
    return ok;
  }

  /// Lets the tool add records to its section, or only read it.
  Future<bool> setSectionAccess(
    Connection connection,
    bool write,
    List<InvitePermission> catalogue,
  ) {
    final keys = {
      for (final k in connection.permissionKeys(catalogue))
        if (!k.startsWith('vault:')) k,
      write ? 'vault:write' : 'vault:read',
    };
    return setPermissions(
      connection.id,
      permissions: [
        for (final k in Connection.toolPermissions)
          if (keys.contains(k)) k,
      ],
    );
  }

  /// Lets the tool read [sectionId] as well, or no longer.
  Future<bool> setSectionReached(
    Connection connection,
    String sectionId,
    bool on,
  ) {
    final next = [
      for (final s in connection.sections)
        if (s != sectionId) s,
      if (on) sectionId,
    ];
    return setPermissions(connection.id, sections: next);
  }

  /// The live tools that can read what is in [sectionId], asked of the
  /// server each time: adding a record there hands it to them. Null when the
  /// answer can't be had, so the caller can still ask before adding.
  Future<List<Connection>?> toolsReaching(String sectionId) async {
    try {
      // Ids are the server's own, letters and digits, so nothing in one can
      // break out of the filter.
      final data = await _api.get(
        _basePath,
        queryParams: {
          'filter': 'section = "$sectionId" || sections ~ "$sectionId"',
          'perPage': '50',
        },
      );
      final items = (data['items'] as List<dynamic>?) ?? const [];
      return [
        for (final e in items) Connection.fromJson(e as Map<String, dynamic>),
      ].where((c) => !c.isExpired && c.reaches(sectionId)).toList();
    } catch (_) {
      return null;
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
      errorMessage = describeError(e);
      return false;
    }
  }
}
