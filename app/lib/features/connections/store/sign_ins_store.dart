import 'package:mobx/mobx.dart';

import 'package:revoked_app/core/config/app_config.dart';
import 'package:revoked_app/core/models/link.dart';
import 'package:revoked_app/core/models/sign_in_service.dart';
import 'package:revoked_app/core/network/api_client.dart';
import 'package:revoked_app/core/network/app_errors.dart';
import 'package:revoked_app/core/state/load_state.dart';

part 'sign_ins_store.g.dart';

// ignore: library_private_types_in_public_api
class SignInsStore = _SignInsStore with _$SignInsStore;

/// The services this account signed in to, and the links holding what it
/// shared with them.
abstract class _SignInsStore with Store {
  final ApiClient _api;

  _SignInsStore(this._api);

  String get _basePath =>
      '/api/collections/${AppConfig.signInsCollection}/records';

  String get _linksPath =>
      '/api/collections/${AppConfig.linksCollection}/records';

  final ObservableList<SignInService> services =
      ObservableList<SignInService>();

  /// Sign-in links in the active workspace, by id. A service's link can be
  /// missing here while it still names one: it lives in another workspace.
  final ObservableMap<String, Link> links = ObservableMap<String, Link>();

  @observable
  String? errorMessage;

  /// A pause, activation or disconnect is on its way.
  @observable
  bool isChanging = false;

  /// The choice in the disconnect dialog: whether the service gets a new ID.
  /// It can't be undone, so it starts off every time the dialog opens.
  @observable
  bool newIdOnDisconnect = false;

  /// Tracks this list for the cache and the first-load skeleton.
  final LoadState loadState = LoadState();

  /// [load], unless what's here is still fresh.
  Future<void> loadIfDue() async {
    if (loadState.isDue) await load();
  }

  @action
  Future<void> load() async {
    errorMessage = null;
    final ticket = loadState.begin();
    try {
      final loaded = <SignInService>[];
      final linked = <String, Link>{};
      try {
        final data = await _api.get(
          _basePath,
          queryParams: {
            'sort': '-lastSignInAt',
            'perPage': '100',
            'expand': 'nameRecord,nameIdentity',
          },
        );
        for (final e in (data['items'] as List<dynamic>?) ?? []) {
          loaded.add(SignInService.fromJson(e as Map<String, dynamic>));
        }
        final linkData = await _api.get(
          _linksPath,
          queryParams: {'filter': 'signInClient != ""', 'perPage': '100'},
        );
        for (final e in (linkData['items'] as List<dynamic>?) ?? []) {
          final link = Link.fromJson(e as Map<String, dynamic>);
          linked[link.id] = link;
        }
      } on ApiException catch (e) {
        // A server older than this app keeps no such list.
        if (e.statusCode != 404) rethrow;
      }
      if (!loadState.isCurrent(ticket)) return;
      runInAction(() {
        services
          ..clear()
          ..addAll(loaded);
        links
          ..clear()
          ..addAll(linked);
      });
      loadState.succeed(ticket);
    } catch (e) {
      if (!loadState.isCurrent(ticket)) return;
      runInAction(() => errorMessage = describeError(e));
      loadState.fail(ticket, errorMessage!);
    }
  }

  /// Refuses new sign-ins at the service and pauses what it may read.
  Future<bool> pause(SignInService service) => _control(service, 'pause');

  /// Undoes [pause].
  Future<bool> activate(SignInService service) => _control(service, 'resume');

  /// Ends what the service can do here, giving it a new ID if
  /// [newIdOnDisconnect] is set. The login it keeps for itself is out of reach.
  Future<bool> disconnect(SignInService service) =>
      _control(service, 'disconnect', {'newId': newIdOnDisconnect});

  @action
  Future<bool> _control(
    SignInService service,
    String action, [
    Map<String, dynamic> body = const {},
  ]) async {
    errorMessage = null;
    isChanging = true;
    try {
      await _api.post('/api/sign-ins/${service.id}/$action', body: body);
      await load();
      return true;
    } catch (e) {
      runInAction(() => errorMessage = describeError(e));
      return false;
    } finally {
      runInAction(() => isChanging = false);
    }
  }

  /// Stops the service reading what was shared with it.
  @action
  Future<bool> revokeLink(Link link) async {
    errorMessage = null;
    try {
      final data = await _api.patch(
        '$_linksPath/${link.id}',
        body: {'status': 'revoked'},
      );
      runInAction(
        () => links[link.id] = Link.fromJson(data as Map<String, dynamic>),
      );
      return true;
    } catch (e) {
      runInAction(() => errorMessage = describeError(e));
      return false;
    }
  }
}
