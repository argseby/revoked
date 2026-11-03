import 'package:mobx/mobx.dart';

import 'package:revoked_app/core/models/webhook.dart';
import 'package:revoked_app/core/network/api_client.dart';
import 'package:revoked_app/core/network/app_errors.dart';
import 'package:revoked_app/core/state/load_state.dart';
import 'package:revoked_app/core/state/observable_text_controller.dart';

part 'webhooks_store.g.dart';

/// Which deliveries the log shows.
enum DeliveryFilter {
  all(null, 'All'),
  failed('failed', 'Failed'),
  pending('pending', 'Waiting'),
  succeeded('succeeded', 'Delivered');

  const DeliveryFilter(this.status, this.label);

  final String? status;
  final String label;
}

/// The active workspace's webhooks, what was sent to each, and the form for a
/// new one.
// ignore: library_private_types_in_public_api
class WebhooksStore = _WebhooksStore with _$WebhooksStore;

abstract class _WebhooksStore with Store {
  final ApiClient _api;

  _WebhooksStore(this._api);

  static const _base = '/api/webhooks';

  final ObservableList<WebhookEndpoint> endpoints =
      ObservableList<WebhookEndpoint>();

  final ObservableList<WebhookEventType> eventTypes =
      ObservableList<WebhookEventType>();

  /// Tracks the endpoint list for the cache and the first-load skeleton.
  final LoadState loadState = LoadState();

  @observable
  String? errorMessage;

  /// A change to an endpoint is on its way.
  @observable
  bool isChanging = false;

  /// The latest deliveries per endpoint, under [filter].
  final ObservableMap<String, List<WebhookDelivery>> deliveries =
      ObservableMap<String, List<WebhookDelivery>>();

  final ObservableSet<String> loadingDeliveries = ObservableSet<String>();

  @observable
  DeliveryFilter filter = DeliveryFilter.all;

  /// Deliveries opened on their own, with payload and every try.
  final ObservableMap<String, WebhookDelivery> details =
      ObservableMap<String, WebhookDelivery>();

  /// The delivery a resend or a test is waiting on.
  @observable
  String? sendingId;

  final ObservableTextController draftUrl = ObservableTextController();
  final ObservableTextController draftDescription = ObservableTextController();

  @observable
  bool draftEverything = true;

  final ObservableSet<String> draftEvents = ObservableSet<String>();

  /// The event the test button sends.
  @observable
  String testType = 'link.revoked';

  @computed
  bool get canCreateDraft =>
      draftUrl.text.trim().isNotEmpty &&
      (draftEverything || draftEvents.isNotEmpty);

  WebhookEndpoint? endpoint(String id) {
    for (final e in endpoints) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// [load], unless what's here is still fresh.
  Future<void> loadIfDue() async {
    if (loadState.isDue) await load();
  }

  @action
  Future<void> load() async {
    errorMessage = null;
    final ticket = loadState.begin();
    try {
      final list = await _api.get('$_base/endpoints');
      final types = eventTypes.isEmpty
          ? await _api.get('$_base/event-types')
          : null;
      if (!loadState.isCurrent(ticket)) return;
      runInAction(() {
        endpoints
          ..clear()
          ..addAll(
            ((list['items'] as List<dynamic>?) ?? const []).map(
              (e) => WebhookEndpoint.fromJson(e as Map<String, dynamic>),
            ),
          );
        if (types != null) {
          eventTypes.addAll(
            ((types['items'] as List<dynamic>?) ?? const []).map(
              (e) => WebhookEventType.fromJson(e as Map<String, dynamic>),
            ),
          );
        }
      });
      loadState.succeed(ticket);
    } catch (e) {
      if (!loadState.isCurrent(ticket)) return;
      runInAction(() => errorMessage = describeError(e));
      loadState.fail(ticket, errorMessage!);
    }
  }

  @action
  void setFilter(DeliveryFilter value, String endpointId) {
    filter = value;
    loadDeliveries(endpointId);
  }

  @action
  Future<void> loadDeliveries(String endpointId) async {
    loadingDeliveries.add(endpointId);
    final asked = filter;
    try {
      final data = await _api.get(
        '$_base/deliveries',
        queryParams: {
          'endpoint': endpointId,
          'perPage': '50',
          if (asked.status != null) 'status': asked.status!,
        },
      );
      if (asked != filter) return;
      runInAction(() {
        deliveries[endpointId] = ((data['items'] as List<dynamic>?) ?? const [])
            .map((e) => WebhookDelivery.fromJson(e as Map<String, dynamic>))
            .toList();
      });
    } catch (e) {
      runInAction(() => errorMessage = describeError(e));
    } finally {
      runInAction(() => loadingDeliveries.remove(endpointId));
    }
  }

  @action
  Future<void> loadDelivery(String id) async {
    try {
      final data = await _api.get('$_base/deliveries/$id');
      runInAction(
        () => details[id] = WebhookDelivery.fromJson(
          data as Map<String, dynamic>,
        ),
      );
    } catch (e) {
      runInAction(() => errorMessage = describeError(e));
    }
  }

  @action
  void resetDraft() {
    draftUrl.clear();
    draftDescription.clear();
    draftEverything = true;
    draftEvents.clear();
  }

  @action
  void setDraftEverything(bool value) => draftEverything = value;

  @action
  void toggleDraftEvent(String type, bool on) {
    if (on) {
      draftEvents.add(type);
    } else {
      draftEvents.remove(type);
    }
  }

  @action
  void setTestType(String type) => testType = type;

  /// Creates the endpoint from the draft and returns its signing secret, the
  /// one time it is handed out unasked.
  @action
  Future<String?> create() async {
    isChanging = true;
    errorMessage = null;
    try {
      final data = await _api.post(
        '$_base/endpoints',
        body: {
          'url': draftUrl.text.trim(),
          'description': draftDescription.text.trim(),
          'events': draftEverything ? ['*'] : draftEvents.toList(),
        },
      );
      final created = WebhookEndpoint.fromJson(data as Map<String, dynamic>);
      runInAction(() => endpoints.insert(0, created));
      loadState.invalidate();
      return data['secret'] as String?;
    } catch (e) {
      runInAction(() => errorMessage = describeError(e));
      return null;
    } finally {
      runInAction(() => isChanging = false);
    }
  }

  Future<bool> setEnabled(String id, bool enabled) =>
      _patch(id, {'enabled': enabled});

  Future<bool> setEvents(String id, List<String> events) =>
      _patch(id, {'events': events});

  @action
  Future<bool> _patch(String id, Map<String, dynamic> body) async {
    isChanging = true;
    errorMessage = null;
    try {
      final data = await _api.patch('$_base/endpoints/$id', body: body);
      _replace(WebhookEndpoint.fromJson(data as Map<String, dynamic>));
      return true;
    } catch (e) {
      runInAction(() => errorMessage = describeError(e));
      return false;
    } finally {
      runInAction(() => isChanging = false);
    }
  }

  @action
  Future<bool> delete(String id) async {
    isChanging = true;
    errorMessage = null;
    try {
      await _api.delete('$_base/endpoints/$id');
      runInAction(() {
        endpoints.removeWhere((e) => e.id == id);
        deliveries.remove(id);
      });
      return true;
    } catch (e) {
      runInAction(() => errorMessage = describeError(e));
      return false;
    } finally {
      runInAction(() => isChanging = false);
    }
  }

  /// The current signing secret, fetched only when someone asks to see it.
  Future<String?> revealSecret(String id) async {
    try {
      final data = await _api.get('$_base/endpoints/$id/secret');
      return data['secret'] as String?;
    } catch (e) {
      runInAction(() => errorMessage = describeError(e));
      return null;
    }
  }

  @action
  Future<String?> rotateSecret(String id) async {
    isChanging = true;
    errorMessage = null;
    try {
      final data = await _api.post('$_base/endpoints/$id/rotate-secret');
      return data['secret'] as String?;
    } catch (e) {
      runInAction(() => errorMessage = describeError(e));
      return null;
    } finally {
      runInAction(() => isChanging = false);
    }
  }

  /// Sends a sample [testType] now and returns what happened to it.
  @action
  Future<WebhookDelivery?> sendTest(String endpointId) async {
    sendingId = endpointId;
    errorMessage = null;
    try {
      final data = await _api.post(
        '$_base/endpoints/$endpointId/test',
        body: {'type': testType},
      );
      final delivery = WebhookDelivery.fromJson(data as Map<String, dynamic>);
      runInAction(() => details[delivery.id] = delivery);
      await _refreshEndpoint(endpointId);
      return delivery;
    } catch (e) {
      runInAction(() => errorMessage = describeError(e));
      return null;
    } finally {
      runInAction(() => sendingId = null);
    }
  }

  @action
  Future<WebhookDelivery?> resend(WebhookDelivery delivery) async {
    sendingId = delivery.id;
    errorMessage = null;
    try {
      final data = await _api.post('$_base/deliveries/${delivery.id}/resend');
      final fresh = WebhookDelivery.fromJson(data as Map<String, dynamic>);
      runInAction(() => details[fresh.id] = fresh);
      await _refreshEndpoint(delivery.endpoint);
      return fresh;
    } catch (e) {
      runInAction(() => errorMessage = describeError(e));
      return null;
    } finally {
      runInAction(() => sendingId = null);
    }
  }

  /// Queues every failed delivery of the last day again; returns how many.
  @action
  Future<int?> resendFailed(String endpointId) async {
    isChanging = true;
    errorMessage = null;
    try {
      final data = await _api.post('$_base/endpoints/$endpointId/replay');
      await _refreshEndpoint(endpointId);
      return (data['queued'] as num?)?.toInt() ?? 0;
    } catch (e) {
      runInAction(() => errorMessage = describeError(e));
      return null;
    } finally {
      runInAction(() => isChanging = false);
    }
  }

  Future<void> _refreshEndpoint(String id) async {
    try {
      final data = await _api.get('$_base/endpoints/$id');
      _replace(WebhookEndpoint.fromJson(data as Map<String, dynamic>));
    } catch (_) {
      // The page still shows the last copy; the next load corrects it.
    }
    await loadDeliveries(id);
  }

  @action
  void _replace(WebhookEndpoint updated) {
    final i = endpoints.indexWhere((e) => e.id == updated.id);
    if (i >= 0) {
      endpoints[i] = updated;
    } else {
      endpoints.insert(0, updated);
    }
  }

  @action
  void forget() {
    endpoints.clear();
    deliveries.clear();
    details.clear();
  }
}
