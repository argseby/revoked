import 'dart:async';

import 'package:mobx/mobx.dart';

import 'package:revoked_app/core/config/app_config.dart';
import 'package:revoked_app/core/models/notification.dart';
import 'package:revoked_app/core/network/api_client.dart';

part 'notifications_store.g.dart';

/// Owner-side in-app notifications.
// ignore: library_private_types_in_public_api
class NotificationsStore = _NotificationsStore with _$NotificationsStore;

abstract class _NotificationsStore with Store {
  final ApiClient _api;

  _NotificationsStore(this._api);

  String get _basePath =>
      '/api/collections/${AppConfig.notificationsCollection}/records';

  final ObservableList<AppNotification> notifications =
      ObservableList<AppNotification>();

  @observable
  bool isLoading = false;

  @observable
  String? errorMessage;

  @computed
  /// @computed, not a bare getter: a plain getter over an empty list
  /// registers no dependency, so the bell that reads it never lights up
  /// when the first notification arrives.
  @computed
  int get unreadCount => notifications.where((n) => !n.read).length;

  /// The server's type for "someone answered your request".
  static const _requestResponse = 'request_response';

  Iterable<AppNotification> _unreadResponses(String requestId) =>
      notifications.where(
        (n) => !n.read && n.type == _requestResponse && n.refId == requestId,
      );

  /// Responses to [requestId] the owner has not looked at yet — the "3 new"
  /// on the Requests list. Read inside an Observer, it follows the list.
  int unreadResponses(String requestId) => _unreadResponses(requestId).length;

  /// Clears the "new" mark once the owner opens a request's responses.
  Future<void> markResponsesRead(String requestId) async {
    for (final n in _unreadResponses(requestId).toList()) {
      await markRead(n.id);
    }
  }

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
      notifications
        ..clear()
        ..addAll(
          items.map((e) => AppNotification.fromJson(e as Map<String, dynamic>)),
        );
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      isLoading = false;
    }
  }

  @action
  Future<void> markRead(String id, {bool read = true}) async {
    try {
      final data = await _api.patch('$_basePath/$id', body: {'read': read});
      final updated = AppNotification.fromJson(data as Map<String, dynamic>);
      final idx = notifications.indexWhere((n) => n.id == id);
      if (idx != -1) notifications[idx] = updated;
    } catch (e) {
      errorMessage = e.toString();
    }
  }

  @action
  Future<void> delete(String id) async {
    try {
      await _api.delete('$_basePath/$id');
      notifications.removeWhere((n) => n.id == id);
    } catch (e) {
      errorMessage = e.toString();
    }
  }

  @action
  Future<void> markAllRead() async {
    final unread = notifications.where((n) => !n.read).toList();
    for (final n in unread) {
      await markRead(n.id);
    }
  }

  @action
  void clearError() => errorMessage = null;

  Timer? _poll;

  /// Keeps the bell current while the app is open. Reminders fire on the
  /// server's clock, not on anything this app does, so nothing else would
  /// bring them in until the next start.
  void startPolling({Duration every = const Duration(minutes: 1)}) {
    _poll?.cancel();
    _poll = Timer.periodic(every, (_) {
      if (!isLoading) load();
    });
  }

  void stopPolling() {
    _poll?.cancel();
    _poll = null;
  }
}
